import json
import struct
import sys
import subprocess
from pathlib import Path
import threading
import time
from test_world import Client


def run(fixtures):
    players, cursors = [], {}
    stop, auto = threading.Event(), threading.Event()
    auto.set()
    root = Path(__file__).resolve().parents[2]
    rows = subprocess.check_output([str(root / 'release/coop/install-base/server/mariadb/bin/mariadb.exe'), '-h', '127.0.0.1', '-u', 'root', '-proot', '-N', '-B', 'mangos', '-e', 'SELECT id FROM bonk_quest WHERE type=33 AND target IN (0,3)'], text=True)
    event_quests = set(rows.split())

    def command(player, text):
        language = 7 if player.fixture['race'] == 1 else 1
        player.send(149, struct.pack('<II', 6, language) + player.fixture['name'].encode() + b'\0' + ('.bonk ' + text).encode() + b'\0')

    def choose():
        while not stop.wait(0.1):
            if not auto.is_set():
                continue
            for player in list(players):
                end = len(player.messages)
                for message in player.messages[cursors.get(player, 0):end]:
                    if message.startswith('BONK~offerend'): command(player, 'pick 1')
                    elif message.startswith('BONK~glyphofferend'): command(player, 'glyph 1')
                    elif message.startswith('BONK~gearoffer~'): command(player, 'gear salvage')
                    elif message.startswith('BONK~leyofferend'): command(player, 'leypick 1')
                cursors[player] = end

    def xp(player):
        return [s for s in player.messages if s.startswith('BONK~runxp~')][-1].split('~')[2:5]

    def quests(player):
        before = len(player.messages)
        command(player, 'quests')
        player.message('BONK~qlogend', since=before)
        return {s.split('~')[2]: s.split('~')[6:9] for s in player.messages[before:] if s.startswith('BONK~q~') and s.split('~')[2] in event_quests}

    worker = threading.Thread(target=choose, daemon=True)
    worker.start()
    try:
        for fixture in fixtures[:2]:
            player = Client(fixture)
            players.append(player)
            player.enter()
            player.command('god')
        host, guest = players
        host.command('start normal')
        host.message('BONK~start~')
        host.send(110, guest.fixture['name'].encode() + b'\0')
        guest.packet(111)
        guest.send(114)
        prompt = guest.message('BONK~coopprompt~', predicate=lambda s: s.split('~')[2] != '0')
        guest.command('coop accept ' + prompt.split('~')[2])
        guest.message('BONK~start~')
        time.sleep(3)
        prior_quests = [quests(p) for p in players]
        before = [len(p.messages) for p in players]
        host.command('event kobolds')
        host.message('BONK~eventtimer~Kobold Thieves~', since=before[0])
        time.sleep(0.5)
        mobs = {s.split('~')[-1] for s in host.messages[before[0]:] if s.startswith('BONK~mob~') and 'kobold' in s.lower()}
        assert len(mobs) == 3, mobs
        for guid in mobs:
            guest.send(317, struct.pack('<Q', int(guid, 16)))
            guest.chat_command('die')
            time.sleep(0.15)
        for index, player in enumerate(players):
            player.message('BONK~msg~You caught every kobold thief!', since=before[index])
        after_quests = [quests(p) for p in players]
        assert after_quests[0] == after_quests[1], (prior_quests, after_quests)
        if event_quests:
            assert after_quests[0] != prior_quests[0], (prior_quests, after_quests)
        assert not any(s.startswith('BONK~gearoffer~') for p, n in zip(players, before) for s in p.messages[n:])
        print('PASS invited player completes kobolds: shared completion, no guest-only gear reward; matching quests:', len(event_quests), flush=True)

        event_quests = {'406'}
        before_quests = [quests(p) for p in players]
        before = [len(p.messages) for p in players]
        host.command('event goblin')
        mob = host.message('BONK~mob~1~', since=before[0], predicate=lambda s: 'goblin' in s.lower())
        guest.send(317, struct.pack('<Q', int(mob.split('~')[-1], 16)))
        guest.chat_command('die')
        for player, cursor in zip(players, before):
            player.message('BONK~msg~You caught the treasure goblin!', since=cursor)
        after_quests = [quests(p) for p in players]
        for index in range(2):
            assert int(after_quests[index]['406'][0]) == int(before_quests[index]['406'][0]) + 1
        print('PASS treasure goblin completion advances the personal event quest for both players', flush=True)

        origin = host.position
        guest.chat_command(f'go xyz {origin[0]+40} {origin[1]} {origin[2]}')
        time.sleep(1)
        auto.clear()
        before = [len(p.messages) for p in players]
        for player in players:
            player.send(317, player.guid)
            player.chat_command('levelup 1')
        for player, cursor in zip(players, before):
            player.message('BONK~offerend', since=cursor)
        host.send(317, host.guid)
        host.chat_command('die')
        host.message('BONK~rescue~Coopalpha~', predicate=lambda s: s.split('~')[4] == '6000')
        after_offer = [len(p.messages) for p in players]
        command(guest, 'pick 1')
        guest.message('BONK~picked', since=after_offer[1])
        time.sleep(1)
        for player, cursor in zip(players, after_offer):
            assert 'BONK~pause~0' not in player.messages[cursor:], 'Pause released before dead player chose'
        command(host, 'pick 1')
        host.message('BONK~picked', since=after_offer[0])
        for player, cursor in zip(players, after_offer):
            player.message('BONK~pause~0', since=cursor)
        print('PASS dead hero chooses via self whisper; faster living hero cannot release the shared pause', flush=True)
        auto.set()
        before_rez = len(host.messages)
        guest.chat_command(f'go xyz {origin[0]} {origin[1]} {origin[2]}')
        host.message('BONK~rescue~Coopalpha~0~0~1', since=before_rez, seconds=25)
        time.sleep(2)
        for player in players:
            assert [s for s in player.messages if s.startswith('BONK~pause~')][-1] == 'BONK~pause~0'
            cursor = len(player.messages)
            command(player, 'dash')
            player.message('BONK~dash~0~', since=cursor)
        print('PASS after resurrection both heroes are unpaused and can dash', flush=True)

        guest.chat_command(f'go xyz {origin[0]+40} {origin[1]} {origin[2]}')
        time.sleep(1)
        host.send(317, host.guid)
        host.chat_command('die')
        dead_cursor = len(host.messages)
        host.message('BONK~rescue~Coopalpha~', since=dead_cursor, predicate=lambda s: s.split('~')[4] == '6000')
        guest.command('skip 600')
        boss = guest.message('BONK~mob~2~')
        time.sleep(3)
        guest.send(317, struct.pack('<Q', int(boss.split('~')[-1], 16)))
        guest.chat_command('die')
        for player in players:
            player.message('BONK~state~', predicate=lambda s: s.split('~')[11] == '1')
        time.sleep(3)
        host.message('BONK~offerend', since=dead_cursor)
        host.message('BONK~picked', since=dead_cursor)
        assert xp(host) == xp(guest), (xp(host), xp(guest))
        print('PASS shared XP creates clickable upgrades for the dead hero and identical progression', xp(host), flush=True)
        guest.chat_command(f'go xyz {origin[0]} {origin[1]} {origin[2]}')
        host.message('BONK~rescue~Coopalpha~0~0~1', since=dead_cursor, seconds=25)
        for player in players: command(player, 'stop')
        for player in players: player.message('BONK~end~')
    except Exception:
        for player in players:
            print(player.fixture['name'], player.messages[-15:], player.system[-8:], flush=True)
        raise
    finally:
        stop.set()
        worker.join(2)
        for player in players: player.close()


if __name__ == '__main__':
    run(json.loads(sys.stdin.readline()))
