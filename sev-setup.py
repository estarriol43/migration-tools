from time import sleep
import base64
import argparse
import asyncio
import sys
from qemu.qmp import QMPClient

parser = argparse.ArgumentParser(description="QEMU/KVM migration helper")
parser.add_argument('--bandwidth', default=1000, type=int, help='Maximum network bandwidth for migration')
parser.add_argument('--multifd', default=0, type=int, metavar='CHANNELS', help='Number of multifd channel for migration (0 for disable)')
parser.add_argument('--postcopy', action='store_true', default=False, help='Enable postcopy for migration')
parser.add_argument('--sev', default='', help='Certicate required for SEV VM migration')
parser.add_argument('--downtime', default=300, help='Maximum tolerable downtime')
parser.add_argument('--dst-ip', default='10.10.1.2', help='IP of destination machine')
parser.add_argument('--src-ip', default='10.10.1.1', help='IP of source machine')
parser.add_argument('--resume-port', default=8888, type=int, help='Port of incoming')
parser.add_argument('--src-qmp', default=1235, type=int, help='QMP port of source VM')
parser.add_argument('--dst-qmp', default=1235, type=int, help='QMP port of destination VM')

async def main():
    args = parser.parse_args(sys.argv[1:])

    dst = QMPClient('dst')
    await dst.connect((args.dst_ip, args.dst_qmp))
    
    src = QMPClient('src')
    await src.connect((args.src_ip, args.src_qmp))

    if args.sev:
        dst_sev = await dst.execute('query-sev-capabilities')
        dst_pdh = dst_sev['pdh']
        dst_plat_certs = dst_sev['cert-chain']

        with open(args.sev, "rb") as ask_ark_file:
            ask_ark_bin = bytearray(ask_ark_file.read())

        amd_cert = str(base64.b64encode(ask_ark_bin), 'ascii')

        ret = await src.execute('migrate-set-parameters', { 'sev-plat-cert' : dst_plat_certs })
        ret = await src.execute('migrate-set-parameters', { 'sev-pdh' : dst_pdh })
        ret = await src.execute('migrate-set-parameters', { 'sev-amd-cert' : amd_cert })

    await src.disconnect()
    await dst.disconnect()

asyncio.run(main())
