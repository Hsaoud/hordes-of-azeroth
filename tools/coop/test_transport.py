import base64
import hashlib
import json
import os
from pathlib import Path
import queue
import socket
import subprocess
import threading
import time


ROOT = Path(__file__).resolve().parent
EXE = ROOT / "target" / "release" / "hoa-coop.exe"


class Peer:
    def __init__(self, mode, **options):
        self.events = queue.Queue()
        self.errors = []
        self.process = subprocess.Popen([str(EXE)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8")
        threading.Thread(target=self.read, daemon=True).start()
        threading.Thread(target=lambda: self.errors.extend(self.process.stderr.readlines()), daemon=True).start()
        config = dict(mode=mode, version="transport-test/1", identity=os.urandom(32).hex().upper())
        config.update(options)
        self.send(config)

    def read(self):
        for line in self.process.stdout:
            self.events.put(json.loads(line))
        self.events.put({"event": "exit"})

    def send(self, value):
        self.process.stdin.write(json.dumps(value) + "\n")
        self.process.stdin.flush()

    def wait(self, event, seconds=65):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            value = self.events.get(timeout=max(0.1, deadline - time.monotonic()))
            if value["event"] == event:
                return value
            if value["event"] in ("error", "exit"):
                raise AssertionError((value, self.errors))
        raise AssertionError(f"No {event} event")

    def close(self):
        try:
            self.send({"command": "stop"})
            self.process.wait(timeout=8)
        except (BrokenPipeError, OSError, subprocess.TimeoutExpired):
            self.process.kill()
            self.process.wait()


def echo_server():
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen()

    def accept():
        while True:
            try:
                stream, _ = listener.accept()
            except OSError:
                return

            def echo(stream):
                with stream:
                    while data := stream.recv(32768):
                        stream.sendall(data)

            threading.Thread(target=echo, args=(stream,), daemon=True).start()

    threading.Thread(target=accept, daemon=True).start()
    return listener


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def round_trip(port):
    with socket.create_connection(("127.0.0.1", port), timeout=20) as stream:
        data = os.urandom(262144)
        received = bytearray()
        sender = threading.Thread(target=stream.sendall, args=(data,))
        sender.start()
        while len(received) < len(data):
            block = stream.recv(32768)
            assert block, "Truncated game stream"
            received.extend(block)
        sender.join()
        assert received == data
        stream.shutdown(socket.SHUT_WR)
        assert stream.recv(1) == b""


def tunnel_round_trip(relay_only=False):
    login, world = echo_server(), echo_server()
    host, guests = None, []
    try:
        host = Peer("host", loginPort=login.getsockname()[1], worldPort=world.getsockname()[1], relayOnly=relay_only)
        code = host.wait("hosting")["code"]
        rejected = Peer("join", code=code, version="incompatible")
        try:
            assert rejected.wait("error")["code"] == "version-mismatch"
        finally:
            rejected.close()
        print("PASS incompatible game versions rejected", flush=True)
        identities, ports = [], []
        for index in range(4):
            identity = os.urandom(32).hex().upper()
            pair = free_port(), free_port()
            identities.append(identity)
            ports.append(pair)
            guests.append(Peer("join", code=code, identity=identity, loginPort=pair[0], worldPort=pair[1], relayOnly=relay_only))
        admissions = [host.wait("guest") for _ in guests]
        profiles = {}
        for index, admission in enumerate(reversed(admissions)):
            assert admission["account"].startswith("COOP") and len(admission["account"]) == 16
            assert len(admission["password"]) == 16
            profile = {"gold": index + 42, "heroes": [{"name": "Testhero", "runs": index, "bestStage": 2}]}
            profiles[admission["account"]] = profile
            host.send({"command": "admit", "request": admission["request"], "profile": profile})
        accounts = []
        for guest in guests:
            ready = guest.wait("ready")
            accounts.append(ready["account"])
            assert ready["profile"] == profiles[ready["account"]]
        for _ in guests:
            host.wait("connected")
        assert len(set(accounts)) == 4
        for pair in ports:
            for port in pair:
                round_trip(port)
        print("PASS four concurrent guests, out-of-order admission and isolated hero profiles", flush=True)
        guests[0].close()
        guests[0] = None
        assert host.wait("left", 20)["account"] == accounts[0]
        round_trip(ports[1][1])
        guests[0] = Peer("join", code=code, identity=identities[0], loginPort=ports[0][0], worldPort=ports[0][1], relayOnly=relay_only)
        admission = host.wait("guest")
        assert admission["account"] == accounts[0]
        host.send({"command": "admit", "request": admission["request"], "profile": profiles[accounts[0]]})
        assert guests[0].wait("ready")["account"] == accounts[0]
        host.wait("connected")
        round_trip(ports[0][1])
        print("PASS guest leave and reconnect without interrupting others; relayOnly=" + str(relay_only), flush=True)
    finally:
        for guest in guests:
            if guest:
                guest.close()
        if host:
            host.close()
        login.close()
        world.close()


def reject_bad_invitation():
    peer = Peer("join", code="HOA1-incomplete")
    try:
        assert peer.wait("error")["code"] == "invalid-code"
        print("PASS malformed invitation rejected before networking", flush=True)
    finally:
        peer.close()


if __name__ == "__main__":
    reject_bad_invitation()
    tunnel_round_trip()
    tunnel_round_trip(relay_only=True)
