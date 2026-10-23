import json
import struct
import sys
import threading
import time
import zlib
from test_world import Client


def gameobjects(player, entry):
    result = set()
    for opcode, payload in player.packets:
        if opcode == 502:
            payload = zlib.decompress(payload[4:])
        elif opcode != 169:
            continue
        for offset in range(len(payload) - 12):
            if payload[offset] not in (2, 3):
                continue
            mask = payload[offset + 1]
            count = mask.bit_count()
            if offset + 2 + count >= len(payload) or payload[offset + 2 + count] != 5:
                continue
            guid, cursor = 0, offset + 2
            for index in range(8):
                if mask & (1 << index):
                    guid |= payload[cursor] << (8 * index)
                    cursor += 1
            if guid >> 48 == 0xF110 and (guid >> 24) & 0xFFFFFF == entry:
                result.add(guid)
    return result


def run(fixtures):
    players, cursors = [], {}
    stop, auto = threading.Event(), threading.Event()
    auto.set()

    def rewards():
        while not stop.wait(0.1):
            if not auto.is_set():
                continue
            for player in list(players):
                end = len(player.messages)
                for text in player.messages[cursors.get(player, 0):end]:
                    if text.startswith("BONK~offerend"):
                        player.command("pick 1")
                    elif text.startswith("BONK~gearoffer~"):
                        player.command("gear salvage")
                    elif text.startswith("BONK~glyphofferend"):
                        player.command("glyph 1")
                    elif text.startswith("BONK~leyofferend"):
                        player.command("leypick 1")
                cursors[player] = end

    worker = threading.Thread(target=rewards, daemon=True)
    worker.start()

    def enter(index):
        player = Client(fixtures[index])
        players.append(player)
        player.enter()
        player.command("god")
        return player

    def join(host, guest):
        before = len(guest.packets)
        host.send(110, guest.fixture["name"].encode() + b"\0")
        guest.packet(111, since=before)
        guest.send(114)
        prompt = guest.message("BONK~coopprompt~", predicate=lambda s: s.split("~")[2] != "0")
        guest.command("coop accept " + prompt.split("~")[2])
        guest.message("BONK~start~")
        time.sleep(2)

    def go(player, x, y, z):
        player.chat_command(f"go xyz {x} {y} {z}")
        time.sleep(0.5)

    def die(player):
        player.send(317, player.guid)
        player.chat_command("die")

    def lastxp(player):
        messages = [s for s in player.messages if s.startswith("BONK~runxp~")]
        return tuple(map(int, messages[-1].split("~")[2:5]))

    try:
        host = enter(0)
        host.command("start normal")
        host.message("BONK~start~")
        guest = enter(1)
        join(host, guest)
        time.sleep(2)
        origin = host.position
        go(guest, origin[0] + 40, origin[1], origin[2])
        before = len(host.messages)
        die(host)
        host.message("BONK~rescue~Coopalpha~", since=before, predicate=lambda s: s.split("~")[4] == "6000")
        host.message("BONK~objective~", since=before, predicate=lambda s: "Revive Coopalpha" in s)
        assert gameobjects(guest, 37) or gameobjects(host, 37), "No tomb object created"
        host.command("stop")
        host.send(346, b"\0")
        time.sleep(2)
        assert not any(s.startswith("BONK~end~") for s in host.messages[before:])
        assert not any(s.startswith("BONK~rescue~Coopalpha~0~0") for s in host.messages[before:])
        print("PASS host death transfers expedition simulation, creates a tomb and blocks surrender/release", flush=True)
        go(guest, *origin[:3])
        progress = host.message("BONK~rescue~Coopalpha~", since=before, predicate=lambda s: 1000 <= int(s.split("~")[3]) < 6000)
        away_cursor = len(host.messages)
        go(guest, origin[0] + 40, origin[1], origin[2])
        host.message("BONK~rescue~Coopalpha~0~6000", since=away_cursor)
        go(guest, *origin[:3])
        started = time.monotonic()
        host.message("BONK~rescue~Coopalpha~0~0~1", since=away_cursor, seconds=15)
        assert time.monotonic() - started >= 4.5
        print("PASS rescue requires continuous nearby presence, resets on departure and revives after six seconds", flush=True)
        before = len(host.messages)
        host.command("dash")
        host.message("BONK~dash~0~", since=before)
        paused_cursor = len(host.messages)
        guest.command("menu 1")
        paused = host.message("BONK~dash~", since=paused_cursor, predicate=lambda s: s.split("~")[7] == "1")
        time.sleep(2)
        resume_cursor = len(host.messages)
        guest.command("menu 0")
        resumed = host.message("BONK~dash~", since=resume_cursor, predicate=lambda s: s.split("~")[7] == "0")
        assert abs(int(paused.split("~")[4]) - int(resumed.split("~")[4])) <= 150, (paused, resumed)
        print("PASS another player's pause freezes authoritative dash recharge and sends the correct remaining time", flush=True)
        guest.command("skip 600")
        boss = guest.message("BONK~mob~2~")
        time.sleep(5)
        guest.send(317, struct.pack("<Q", int(boss.split("~")[-1], 16)))
        guest.chat_command("die")
        for player in players:
            player.message("BONK~state~", predicate=lambda s: s.split("~")[11] == "1")
        time.sleep(3)
        assert lastxp(host) == lastxp(guest), (lastxp(host), lastxp(guest))
        assert lastxp(host)[0] > 1 or lastxp(host)[1] > 0, "No XP collected"
        print("PASS collected orb XP and level progress are identical for both heroes", lastxp(host), flush=True)
        third = enter(2)
        join(host, third)
        assert lastxp(third) == lastxp(host), (lastxp(third), lastxp(host))
        print("PASS late arrival catches up to the exact shared level and XP", flush=True)
        chest = guest.message("BONK~objective~", predicate=lambda s: s.split("~")[3] == "chest" and "Opens for free" in s)
        fields = chest.split("~")
        guest.chat_command(f"go xy {fields[4]} {fields[5]} {fields[6]}")
        time.sleep(2)
        chests = gameobjects(guest, 900002)
        assert chests, "No free chest object visible"
        auto.clear()
        before_chest = [len(p.messages) for p in players]
        for guid in chests:
            guest.send(177, struct.pack("<Q", guid))
        for index, player in enumerate(players):
            player.message("BONK~offerend", since=before_chest[index])
        offers = [[s for s in p.messages[before_chest[i]:] if s.startswith("BONK~opt~")] for i, p in enumerate(players)]
        assert all(offers) and len({tuple(o) for o in offers}) == len(players), offers
        for guid in chests:
            guest.send(177, struct.pack("<Q", guid))
        time.sleep(0.5)
        for index, player in enumerate(players):
            assert sum(s.startswith("BONK~offerend") for s in player.messages[before_chest[index]:]) == 1
        print("PASS an invited hero opens one chest: all three receive distinct personal offers, without duplicate rewards", flush=True)
        auto.set()
        time.sleep(3)
        before_wipe = [len(p.messages) for p in players]
        for player in players:
            die(player)
        for index, player in enumerate(players):
            player.message("BONK~end~", since=before_wipe[index], seconds=15)
        print("PASS complete party defeat ends the expedition for every hero", flush=True)
    except Exception:
        for player in players:
            print(player.fixture["name"], player.position, "MESSAGES", player.messages[-20:], "SYSTEM", player.system[-12:], flush=True)
        raise
    finally:
        stop.set()
        worker.join(2)
        for player in players:
            player.close()


if __name__ == "__main__":
    run(json.loads(sys.stdin.readline()))
