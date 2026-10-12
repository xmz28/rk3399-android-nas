"""Run ONLY inside an isolated, disposable clean-image chroot.

No real NAS bind mount is allowed. All test services use separate ports.
"""
from pathlib import Path
import ftplib
import importlib.util
import json
import os
import subprocess
import time
import urllib.request
import paramiko

os.environ['PATH'] = '/usr/sbin:/usr/bin:/sbin:/bin'
assert Path('/etc/nas-clean-image').exists()
assert not Path('/etc/copyparty-base.conf').exists(), 'Use a fresh disposable rootfs'
assert not os.path.ismount('/mnt/nas'), 'Never test against real NAS data'
fixture = 'Isolated_Fixture_20261012'
credential = Path('/tmp/test-credentials.json')
credential.write_text(json.dumps({'password': fixture}))
subprocess.run(['/usr/bin/python3', '/tmp/initialize-nas.py', str(credential)], check=True)
assert not credential.exists()
subprocess.run(['/usr/bin/python3', '/tmp/prepare-nas.py', '/tmp/smb.conf'], check=True)
Path('/mnt/nas/test.txt').write_text('isolated clean image test\n')
subprocess.run(['/usr/bin/python3', '/tmp/nas-volumes.py', '--stage'], check=True)
smb = Path('/etc/samba/smb.conf').read_text().replace('smb ports = 445', 'smb ports = 1445')
Path('/run/test-smb.conf').write_text(smb)
nginx = Path('/tmp/nas-portal-nginx.conf').read_text().replace('listen 80;', 'listen 18080;').replace(':3923;', ':13923;')
nginx = nginx.replace(':3002/', ':13002/')
Path('/run/test-nginx.conf').write_text(nginx)
Path('/etc/nginx/nas-extra').mkdir(exist_ok=True)
speedconf = Path('/tmp/nas-speedtest-nginx.conf').read_text().replace('listen 3000;', 'listen 13000;')
Path('/etc/nginx/nas-extra/speedtest.conf').write_text(speedconf)
Path('/opt/openspeedtest/downloading').write_bytes(bytes(range(256)) * (30 * 1024 * 1024 // 256))
relay = Path('/tmp/nas-speedtest-relay.py').read_text().replace('3000', '13000').replace('3002', '13002')
Path('/run/test-relay.py').write_text(relay)
processes = []
logs = []
try:
    for name, command in (
        ('smb', ['/usr/sbin/smbd', '-F', '--no-process-group', '-s', '/run/test-smb.conf']),
        ('copyparty', ['/usr/bin/python3', '/opt/copyparty-sfx.py', '-c', '/run/copyparty-stage.conf']),
        ('nginx', ['/usr/sbin/nginx', '-c', '/run/test-nginx.conf', '-g', 'daemon off;']),
        ('relay', ['/usr/bin/python3', '/run/test-relay.py']),
    ):
        log = open('/tmp/test-' + name + '.log', 'w')
        logs.append(log)
        processes.append(subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=log,
                                          stderr=log, start_new_session=True))
    for attempt in range(30):
        try:
            urllib.request.urlopen('http://127.0.0.1:18080/', timeout=2).read()
            ftp = ftplib.FTP()
            ftp.connect('127.0.0.1', 12346, timeout=2)
            ftp.login('admin', fixture)
            break
        except OSError:
            time.sleep(1)
    else:
        raise RuntimeError('Test services failed to start')
    result = []
    ftp.retrlines('RETR /NAS/test.txt', result.append)
    ftp.quit()
    assert result == ['isolated clean image test']
    print('FTP_READ=PASS')
    transport = paramiko.Transport(('127.0.0.1', 1235))
    transport.connect(username='admin', password=fixture)
    sftp = paramiko.SFTPClient.from_transport(transport)
    assert sftp.open('/NAS/test.txt').read() == b'isolated clean image test\n'
    sftp.close()
    transport.close()
    print('SFTP_READ=PASS')
    password_manager = urllib.request.HTTPPasswordMgrWithDefaultRealm()
    password_manager.add_password(None, 'http://127.0.0.1:18080/', 'admin', fixture)
    opener = urllib.request.build_opener(urllib.request.HTTPBasicAuthHandler(password_manager))
    request = urllib.request.Request('http://127.0.0.1:18080/files/NAS/test.txt')
    # Copyparty supports pw cookie for clients without its browser session.
    request.add_header('Cookie', 'cppwd=' + fixture)
    assert opener.open(request, timeout=5).read() == b'isolated clean image test\n'
    print('HTTP_REVERSE_PROXY_READ=PASS')
    subprocess.run(['/usr/bin/smbclient', '//127.0.0.1/NAS', '-p', '1445',
                    '-U', 'admin%' + fixture, '-c', 'get test.txt /tmp/smb-read.txt'], check=True)
    assert Path('/tmp/smb-read.txt').read_text() == 'isolated clean image test\n'
    print('SMB_READ=PASS')
    page = urllib.request.urlopen('http://127.0.0.1:18080/speedtest/', timeout=5).read()
    assert b'OpenSpeedTest' in page
    response = urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:18080/speedtest/downloading', method='HEAD'), timeout=5)
    assert response.headers['Content-Length'] == str(30 * 1024 * 1024)
    assert len(response.headers.get_all('Content-Length')) == 1
    response = urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:18080/speedtest/upload', data=b'X' * 32768), timeout=5)
    assert response.status == 200
    response = urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:18080/speedtest/upload', method='OPTIONS'), timeout=5)
    assert response.status == 200
    print('SPEEDTEST_PROXY_GET_HEAD_POST_OPTIONS=PASS (not throughput measurement)')
    for process in processes:
        assert process.poll() is None, 'Test process exited early'
    print('CLEAN_IMAGE_PROTOCOL_CHECK=PASS')
finally:
    for process in processes:
        process.terminate()
    for process in processes:
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    for log in logs:
        log.close()
