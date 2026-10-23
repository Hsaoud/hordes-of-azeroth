import json
import re
import struct
import sys
import threading
import time
from test_world import Client


def run(fixtures):
    players = []
    stop = threading.Event()
    cursors = {}

    def rewards():
        while not stop.wait(0.1):
            for player in list(players):
                if player.closed:
                    continue
                cursor = cursors.get(player, 0)
                end = len(player.messages)
                for text in player.messages[cursor:end]:
                    if text.startswith("BONK~offerend"):
                        player.command("pick 1")
                    elif text.startswith("BONK~gearoffer~"):
                        player.command("gear salvage")
                    elif text.startswith("BONK~glyphofferend"):
                        player.command("glyph 1")
                cursors[player] = end

    chooser = threading.Thread(target=rewards, daemon=True)
    chooser.start()

    def enter(index):
        player = Client(fixtures[index])
        players.append(player)
        player.enter()
        player.command("god")
        return player

    def invite(leader, member):
        before = len(member.packets)
        leader.send(110, member.fixture["name"].encode() + b"\0")
        member.packet(111, since=before)
        member.send(114)

    def answer(member, accept=True, since=0):
        prompt = member.message("BONK~coopprompt~", since=since, predicate=lambda text: text.split("~")[2] != "0")
        token = prompt.split("~")[2]
        member.command("coop " + ("accept " if accept else "decline ") + token)
        return token

    def health(player, guid):
        player.send(317, struct.pack("<Q", guid))
        before = len(player.system)
        player.command("mobinfo")
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            for text in player.system[before:]:
                match = re.search(r"health (\d+) of (\d+)", text)
                if match:
                    return tuple(map(int, match.groups()))
            time.sleep(0.1)
        raise AssertionError(("No creature health", player.system[-10:]))

    try:
        first = enter(0)
        first.command("start normal")
        start = first.message("BONK~start~")
        time.sleep(3)
        print("PASS host starts an expedition before anyone connects: " + start, flush=True)
        first.command("skip 600")
        boss = first.message("BONK~mob~2~")
        boss_guid = int(boss.split("~")[-1], 16)
        first.command("menu 1")
        time.sleep(1)
        hp_one = health(first, boss_guid)
        second = enter(1)
        assert not any(text.startswith("BONK~start~") for text in second.messages)
        invite(first, second)
        answer(second)
        second.message("BONK~start~")
        second.message("BONK~coop~", predicate=lambda text: text.split("~")[2] == "2")
        hp_two = health(first, boss_guid)
        assert abs(hp_two[1] / hp_one[1] - 1.7) < 0.015, (hp_one, hp_two)
        assert abs(hp_two[0] / hp_two[1] - hp_one[0] / hp_one[1]) < 0.02
        print("PASS late connection, native cross-faction party, popup travel and live 2-player health scaling", flush=True)
        third = enter(2)
        invite(first, third)
        token = answer(third, False)
        time.sleep(2)
        assert not any(text.startswith("BONK~start~") for text in third.messages)
        cursor = len(third.messages)
        third.command("coop join")
        answer(third, since=cursor)
        third.message("BONK~start~")
        third.message("BONK~coop~", predicate=lambda text: text.split("~")[2] == "3")
        hp_three = health(first, boss_guid)
        assert abs(hp_three[1] / hp_one[1] - 2.4) < 0.02, (hp_one, hp_three)
        print("PASS third hero can decline, then join; shared boss scales to three participants", flush=True)
        cursor = len(third.messages)
        third.command("coop accept " + token)
        time.sleep(0.5)
        assert not any(text.startswith("BONK~start~") for text in third.messages[cursor:])
        first.command("menu 0")
        first.chat_command("die")
        for player in players:
            player.message("BONK~state~", predicate=lambda text: text.split("~")[11] == "1")
        time.sleep(2)
        before = [len(player.messages) for player in players]
        first.command("skip")
        second.command("skip")
        time.sleep(1)
        assert not any(text.startswith("BONK~start~") for text in first.messages[before[0]:])
        third.command("skip")
        starts = [player.message("BONK~start~", since=cursor, predicate=lambda text: text.split("~")[5] == "2") for player, cursor in zip(players, before)]
        assert len(set(starts)) == 1, starts
        print("PASS shared boss completion, all three portal confirmations and synchronized next stage", flush=True)
        before_first, before_third = len(first.messages), len(third.messages)
        second.command("stop")
        second.message("BONK~end~")
        first.message("BONK~coop~", since=before_first, predicate=lambda text: text.split("~")[2] == "2")
        assert not any(text.startswith("BONK~end~") for text in third.messages[before_third:])
        print("PASS one member leaves while the expedition continues", flush=True)
        before_third = len(third.messages)
        first.close()
        third.message("BONK~coop~", since=before_third, seconds=45, predicate=lambda text: text.split("~")[2] == "1")
        third.message("BONK~state~", since=before_third, predicate=lambda text: int(text.split("~")[2]) > 2)
        assert not any(text.startswith("BONK~end~") for text in third.messages[before_third:])
        print("PASS expedition owner disconnect transfers the world to a remaining member", flush=True)
        third.command("stop")
        third.message("BONK~end~", since=before_third)
        time.sleep(7)
        second.send(123)
        third.send(123)
        time.sleep(1)
        invite(second, third)
        before_second, before_third = len(second.messages), len(third.messages)
        third.command("start normal")
        second.message("BONK~coopprompt~", since=before_second, predicate=lambda text: text.split("~")[2] != "0")
        assert not any(text.startswith("BONK~start~") for text in third.messages[before_third:])
        third.command("coop cancel")
        second.message("BONK~coopprompt~0", since=before_second)
        before_second, before_third = len(second.messages), len(third.messages)
        third.command("start normal")
        answer(second, since=before_second)
        second.message("BONK~start~", since=before_second)
        third.message("BONK~start~", since=before_third)
        print("PASS a non-leader proposes a mission, can cancel, then starts after group acceptance", flush=True)
    except Exception:
        for player in players:
            print(player.fixture["name"], "LAST MESSAGES", player.messages[-15:], "SYSTEM", player.system[-12:], flush=True)
        raise
    finally:
        stop.set()
        chooser.join(timeout=2)
        for player in players:
            player.close()


if __name__ == "__main__":
    run(json.loads(sys.stdin.readline()))
