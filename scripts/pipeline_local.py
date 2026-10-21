#!/usr/bin/env python3
"""Entrega local. Python 3.10+, Windows/PowerShell e Linux/Bash."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]

def run(argv, *, capture=False):
    print('+ ' + ' '.join(map(str, argv)), flush=True)
    return subprocess.run(argv, cwd=ROOT, check=True, text=True,
                          encoding='utf-8', errors='replace',
                          capture_output=capture)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('version', nargs='?', default='v2')
    parser.add_argument('replicas', nargs='?', type=int, default=3)
    args = parser.parse_args()
    if not re.fullmatch(r'v[1-9][0-9]*', args.version):
        parser.error('Use v1, v2, v3...; o incidente e realizado manualmente')
    if not 1 <= args.replicas <= 10:
        parser.error('Replicas: 1 a 10')
    docker = shutil.which('docker')
    minikube = shutil.which('minikube')
    if not docker or not minikube:
        raise RuntimeError('Docker ou Minikube nao encontrado no PATH')
    build = ROOT/'build'
    evidence = ROOT/'evidencias'
    build.mkdir(exist_ok=True)
    evidence.mkdir(exist_ok=True)
    kube = [minikube, '-p', 'devops-k8s', 'kubectl', '--',
            '--context=devops-k8s', '--namespace=aula-k8s']
    image = 'entrega-local:' + args.version
    run([docker, 'info'], capture=True)
    run([minikube, '-p', 'devops-k8s', 'status'], capture=True)
    run([sys.executable, '-m', 'unittest', 'discover', '-s', 'tests', '-v'])
    exists = subprocess.run([docker, 'image', 'inspect', image], cwd=ROOT,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if exists.returncode == 0:
        raise RuntimeError('Essa tag ja existe. Use a proxima versao, como v4.')
    run([docker, 'build', '--build-arg', 'APP_VERSION='+args.version, '-t', image, '.'])
    run([minikube, '-p', 'devops-k8s', 'image', 'load', image])
    run([sys.executable, 'scripts/render.py', args.version, '--replicas',
         str(args.replicas), '--output', 'build/deployment.yaml'])
    for manifest in ['k8s/namespace.yaml', 'k8s/configmap.yaml',
                     'k8s/service.yaml', 'build/deployment.yaml']:
        run(kube + ['apply', '-f', manifest])
    run(kube + ['rollout', 'status', 'deployment/entrega', '--timeout=120s'])
    logpath = build/'pipeline-port-forward.log'
    with logpath.open('w', encoding='utf-8') as log:
        options = {'start_new_session': True} if os.name != 'nt' else {
            'creationflags': subprocess.CREATE_NEW_PROCESS_GROUP}
        proc = subprocess.Popen(kube+['port-forward', 'service/entrega', '18080:80'],
                                cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                **options)
        try:
            for _ in range(80):
                content = logpath.read_text(encoding='utf-8', errors='replace')
                if proc.poll() is not None:
                    raise RuntimeError('Port-forward encerrou: '+content)
                if 'Forwarding from 127.0.0.1:18080' in content:
                    break
                time.sleep(.25)
            else:
                raise RuntimeError('Porta 18080 nao abriu. Consulte '+str(logpath))
            run([sys.executable, 'scripts/smoke.py', 'http://127.0.0.1:18080',
                 '--version', args.version, '--output',
                 'evidencias/status-'+args.version+'.json'])
        finally:
            # Encerrar a arvore criada pelo script, inclusive kubectl filho.
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            else:
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                if os.name != 'nt':
                    try: os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError: pass
                proc.wait(timeout=5)
    pods = run(kube+['get', 'pods', '-l', 'app=entrega', '-o', 'wide'], capture=True)
    (evidence/('pods-'+args.version+'.txt')).write_text(pods.stdout, encoding='utf-8')
    info = run([docker, 'image', 'inspect', image], capture=True)
    image_id = json.loads(info.stdout)[0]['Id']
    (evidence/('imagem-'+args.version+'.txt')).write_text(image_id+'\n', encoding='utf-8')
    print('Pipeline concluida: '+args.version+', replicas='+str(args.replicas))

if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print('PIPELINE FALHOU: '+str(error), file=sys.stderr)
        raise SystemExit(1)
