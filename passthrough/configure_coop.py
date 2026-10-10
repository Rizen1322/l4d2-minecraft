"""Configure an opt-in private LAN room; never modifies firewall or launches games."""
import argparse
import getpass
import json
import os
from pathlib import Path
import secrets
from coop import load_config

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=('host','join','off'))
    parser.add_argument('--server',help='Listen host LAN hostname/IP')
    parser.add_argument('--userid',type=int,help='Your userid from L4D2 console status on the host')
    parser.add_argument('--player',help='Your exact Steam/L4D2 display name; resolves changed userids after reconnect')
    args=parser.parse_args();path=ROOT/'l4d2mc.coop.json'
    if args.mode=='off':
        if path.exists():path.unlink()
        print('Co-op disabled. The next launch uses a local solo session.');return
    if args.mode=='host':value={'mode':'host','bind':'0.0.0.0','port':25602,'token':secrets.token_urlsafe(32)}
    else:
        if not args.server or (args.userid is None and not args.player):parser.error('join requires --server and --player (or --userid)')
        value={'mode':'join','server':f'ws://{args.server}:25602','l4d2server':f'{args.server}:27015',
               'userid':args.userid,
               # The Coop.bat wizard passes the token from the host's invite code through the
               # environment, so it never appears on a command line or in shell history.
               'token':os.environ.get('L4D2MC_ROOM_TOKEN') or getpass.getpass('Private token from the host local config: ')}
        if args.player:value['player']=args.player
    staging=path.with_suffix('.json.tmp');staging.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
    try:load_config(staging)
    except ValueError as error:staging.unlink();parser.error(str(error))
    staging.replace(path)
    print('Saved private l4d2mc.coop.json. Close the current launcher before relaunching.')
    if args.mode=='host':print('Share the token from this local file privately with your teammate. See docs/COOP.md.')

if __name__=='__main__':main()
