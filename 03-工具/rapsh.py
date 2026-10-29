#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Run a local shell script on the phone over ssh.

usage: python rapsh.py <script.sh> [sudo] [host]
       sudo  -> log in as user/1234 and wrap with sudo -S (password piped)
"""
import sys, io
import paramiko

script_path = sys.argv[1]
use_sudo = len(sys.argv) > 2 and sys.argv[2] == 'sudo'
host = sys.argv[3] if len(sys.argv) > 3 else '172.16.42.1'

body = io.open(script_path, 'rb').read().decode('utf-8')

if use_sudo:
    body = "cat > /tmp/_dsh_run.sh <<'EOS_RUN'\n" + body + "\nEOS_RUN\nprintf '1234\\n' | sudo -S -p '' bash /tmp/_dsh_run.sh 2>&1\n"

c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect(host, 22, 'user', '1234', timeout=25, banner_timeout=30,
          look_for_keys=False, allow_agent=False)

stdin, stdout, stderr = c.exec_command('bash -s', timeout=900)
stdin.write(body)
stdin.channel.shutdown_write()
out = stdout.read().decode('utf-8', 'replace')
err = stderr.read().decode('utf-8', 'replace')
code = stdout.channel.recv_exit_status()
sys.stdout.write(out)
if err.strip():
    sys.stdout.write('\n[STDERR]\n' + err)
sys.stdout.write('\n[exit %d]\n' % code)
c.close()
