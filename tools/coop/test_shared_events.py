import json
import sys
import threading
import time
from test_world import Client


def run(fixtures):
    players, cursors = [], {}
    stop = threading.Event()

    def choose():
        while not stop.wait(0.1):
            for player in list(players):
                end = len(player.messages)
                for message in player.messages[cursors.get(player, 0):end]:
                    if message.startswith('BONK~offerend'): player.command('pick 1')
                    elif message.startswith('BONK~glyphofferend'): player.command('glyph 1')
                    elif message.startswith('BONK~gearoffer~'): player.command('gear salvage')
                    elif message.startswith('BONK~leyofferend'): player.command('leypick 1')
                cursors[player] = end

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
        time.sleep(2)
        before = len(host.messages)
        host.command('shrine leyline')
        objective = host.message('BONK~objective~', since=before, predicate=lambda s: 'Ley Line' in s).split('~')
        before_rewards = [len(p.messages) for p in players]
        host.chat_command(f'go xy {float(objective[4])+30} {objective[5]} {objective[6]}')
        guest.chat_command(f'go xy {objective[4]} {objective[5]} {objective[6]}')
        guest.message('BONK~capture~Ley Line~', since=before_rewards[1], seconds=20)
        for index, player in enumerate(players):
            player.message('BONK~leyofferend', since=before_rewards[index], seconds=30)
        print('PASS a guest captures a Ley Line away from the host; both receive independent rewards', flush=True)
        time.sleep(2)
        for player in players: player.command('stop')
        for player in players: player.message('BONK~end~')
    except Exception:
        for player in players:
            print(player.fixture['name'], player.messages[-12:], player.system[-12:], flush=True)
        raise
    finally:
        stop.set()
        worker.join(2)
        for player in players: player.close()


if __name__ == '__main__':
    run(json.loads(sys.stdin.readline()))
