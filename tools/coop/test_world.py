import hashlib
import json
import re
import socket
import struct
import sys
import threading
import time
import zlib
from auth_client import authenticate


class Client:
    def __init__(self, fixture):
        self.fixture = fixture
        self.key = authenticate(fixture["account"], fixture["password"]) if "password" in fixture else bytes.fromhex(fixture["key"])
        self.send_index = self.send_last = self.recv_index = self.recv_last = 0
        self.crypted = False
        self.messages = []
        self.system = []
        self.packets = []
        self.position = (16242.1, 16304.9, 20.899, 6.1865)
        self.lock = threading.Lock()
        self.socket = socket.create_connection(("127.0.0.1", 8085), timeout=15)
        self.socket.settimeout(60)
        opcode, data = self.receive()
        assert opcode == 492
        seed = struct.unpack("<I", data[:4])[0]
        client_seed = 12345
        account = fixture["account"].encode()
        digest = hashlib.sha1(account + struct.pack("<III", 0, client_seed, seed) + self.key).digest()
        self.send(493, struct.pack("<II", 5875, 0) + account + b"\0" + struct.pack("<I", client_seed) + digest + struct.pack("<I", 0))
        self.crypted = True
        opcode, data = self.receive()
        while opcode != 494:
            opcode, data = self.receive()
        assert data[0] == 12, ("World login refused", data[0])
        self.closed = False
        self.failure = None
        self.reader = threading.Thread(target=self.read, daemon=True)
        self.reader.start()

    def exact(self, length):
        result = bytearray()
        while len(result) < length:
            part = self.socket.recv(length - len(result))
            if not part:
                raise EOFError("Game connection closed")
            result.extend(part)
        return result

    def receive(self):
        header = self.exact(4)
        if self.crypted:
            for index, byte in enumerate(header):
                header[index] = ((byte - self.recv_last) & 255) ^ self.key[self.recv_index % len(self.key)]
                self.recv_index += 1
                self.recv_last = byte
        length = struct.unpack(">H", header[:2])[0]
        opcode = struct.unpack("<H", header[2:])[0]
        return opcode, bytes(self.exact(length - 2))

    def send(self, opcode, data=b""):
        with self.lock:
            header = bytearray(struct.pack(">H", len(data) + 4) + struct.pack("<I", opcode))
            if self.crypted:
                for index, byte in enumerate(header):
                    encoded = ((byte ^ self.key[self.send_index % len(self.key)]) + self.send_last) & 255
                    header[index] = encoded
                    self.send_last = encoded
                    self.send_index += 1
            self.socket.sendall(header + data)

    def read(self):
        try:
            while not self.closed:
                opcode, data = self.receive()
                self.packets.append((opcode, data))
                if opcode == 62:
                    self.position = struct.unpack("<ffff", data[4:20])
                    self.send(220)
                if opcode == 566:
                    self.position = struct.unpack("<ffff", data[4:20])
                if opcode == 199:
                    count = data[0].bit_count()
                    counter = data[1 + count:5 + count]
                    movement = data[5 + count:]
                    self.position = struct.unpack("<ffff", movement[8:24])
                    self.send(199, self.guid + counter + struct.pack("<I", 0))
                if opcode == 150:
                    for field in data.split(b"\0"):
                        if len(field) > 8:
                            self.system.append(field.decode("utf-8", errors="replace"))
                        if b"BONK~" in field:
                            text = field[field.index(b"BONK~"):].decode("utf-8", errors="replace")
                            self.messages.append(text)
        except Exception as error:
            if not self.closed:
                self.failure = error

    def packet(self, opcode, since=0, seconds=35):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            for op, data in self.packets[since:]:
                if op == opcode:
                    return data
            if self.failure:
                raise self.failure
            time.sleep(0.05)
        raise AssertionError(f"No packet {opcode}")

    def message(self, prefix, since=0, seconds=35, predicate=lambda text: True):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            for text in self.messages[since:]:
                if text.startswith(prefix) and predicate(text):
                    return text
            if self.failure:
                raise self.failure
            time.sleep(0.05)
        raise AssertionError(f"No {prefix}: {self.messages[-12:]}")

    def command(self, text):
        self.chat_command("bonk " + text)

    def chat_command(self, text):
        language = 7 if self.fixture["race"] == 1 else 1
        self.send(149, struct.pack("<II", 0, language) + ("." + text).encode() + b"\0")

    def enter(self):
        self.send(55)
        assert self.packet(59)[0] == 0
        before = len(self.packets)
        self.send(54, self.fixture["name"].encode() + b"\0" + bytes([self.fixture["race"], self.fixture["heroClass"], 0, 0, 0, 0, 0, 0, 0]))
        response = self.packet(58)
        assert response[0] == 46, ("Character creation failed", response[0])
        self.send(55)
        characters = self.packet(59, since=before)
        assert characters[0] == 1
        self.guid = characters[1:9]
        self.send(61, characters[1:9])
        self.packet(566)
        time.sleep(2)
        self.command("hello")
        self.message("BONK~hello")

    def close(self):
        self.closed = True
        self.socket.close()


def run(fixtures):
    players = []
    try:
        for fixture in fixtures:
            player = Client(fixture)
            players.append(player)
            player.enter()
        first, second = players
        first.message("BONK~coop~Coopbeta")
        second.message("BONK~coop~Coopalpha")
        print("PASS two real heroes, different classes and factions, automatic party", flush=True)
        if fixtures[0].get("extended"):
            first.command("god")
            second.command("god")
        first.command("start normal")
        first.message("BONK~coop~Coopbeta~1")
        assert not any(text.startswith("BONK~start~") for text in first.messages)
        first.command("stop")
        first.message("BONK~coop~Coopbeta~0", since=len(first.messages) - 1)
        print("PASS first player ready, no early start, ready cancellation", flush=True)
        first.command("start normal")
        first.message("BONK~coop~Coopbeta~1", since=len(first.messages) - 1)
        second.command("start normal")
        start_one = first.message("BONK~start~")
        start_two = second.message("BONK~start~")
        assert start_one == start_two, (start_one, start_two)
        print("PASS confirmed start in the same stage: " + start_one, flush=True)
        before = len(second.messages)
        first.command("menu 1")
        second.message("BONK~coop~", since=before, predicate=lambda text: text.split("~")[5] == "1")
        first.command("menu 0")
        print("PASS one player's menu pauses both heroes", flush=True)
        if fixtures[0].get("extended"):
            cursors = [len(player.messages) for player in players]

            def choose_rewards(seconds):
                deadline = time.monotonic() + seconds
                while time.monotonic() < deadline:
                    for index, player in enumerate(players):
                        for text in player.messages[cursors[index]:]:
                            if text.startswith("BONK~offerend"):
                                player.command("pick 1")
                        cursors[index] = len(player.messages)
                    time.sleep(0.1)

            choose_rewards(25)
            for player in players:
                player.message("BONK~state~", predicate=lambda text: int(text.split("~")[4]) > 0)
            print("PASS both heroes fight the same horde and receive kill credit", flush=True)
            before_one, before_two = len(first.messages), len(second.messages)
            first.command("skip 600")
            boss = first.message("BONK~mob~2~", since=before_one)
            guid = int(boss.split("~")[-1], 16)
            first.send(317, struct.pack("<Q", guid))
            first.chat_command("die")
            first.message("BONK~state~", since=before_one, predicate=lambda text: text.split("~")[11] == "1")
            second.message("BONK~state~", since=before_two, predicate=lambda text: text.split("~")[11] == "1")
            choose_rewards(2)
            before_one, before_two = len(first.messages), len(second.messages)
            first.command("skip")
            time.sleep(1)
            assert not any(text.startswith("BONK~start~") for text in first.messages[before_one:])
            second.command("skip")
            stage_one = first.message("BONK~start~", since=before_one, predicate=lambda text: text.split("~")[5] == "2")
            stage_two = second.message("BONK~start~", since=before_two, predicate=lambda text: text.split("~")[5] == "2")
            assert stage_one == stage_two
            print("PASS boss clear, two portal confirmations and synchronized stage 2", flush=True)
        first.command("stop")
        first.message("BONK~end~")
        second.message("BONK~end~")
        print("PASS shared end of run", flush=True)
        time.sleep(6)
        before_one, before_two = len(first.messages), len(second.messages)
        first.command("start normal")
        first.message("BONK~coop~Coopbeta~1", since=before_one)
        second.command("start normal")
        first.message("BONK~start~", since=before_one)
        second.message("BONK~start~", since=before_two)
        before = len(first.messages)
        second.close()
        first.message("BONK~end~", since=before, seconds=45)
        print("PASS guest disconnect ends the shared run", flush=True)
    finally:
        for player in players:
            player.close()


if __name__ == "__main__":
    run(json.loads(sys.stdin.readline()))
