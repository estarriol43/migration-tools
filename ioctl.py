import sys

send = []
receive = []

with open(sys.argv[1], 'r') as f:
    lines = f.readlines()
    for line in lines:
        if line.find('SEND_UPDATE_DATA') != -1:
            send.append(int(line.split(':')[-1]))
        elif line.find('RECEIVE_UPDATE_DATA') != -1:
            receive.append(int(line.split(':')[-1]))

send.sort()
receive.sort()

send = send[int(len(send)*0.05):-int(len(send)*0.05)]
receive = receive[int(len(receive)*0.05):-int(len(receive)*0.05)]

if send:
    print(f'send: {sum(send)/len(send)}')
if receive:
    print(f'receive: {sum(receive)/len(receive)}')

