"""새로 공개되거나 고친 페이지를 IndexNow 로 네이버(·빙 등)에 알림.

쓰는 법: python3 tools/indexnow.py <예전 sitemap.xml> <새 sitemap.xml>
- 새 사이트맵에만 있는 주소, lastmod 가 바뀐 주소만 보냄 (바뀐 게 없으면 아무것도 안 함)
- GitHub Pages 에 실제로 올라간 뒤(200 응답) 보냄. 최대 10분 기다림
- 실패해도 빌드는 멈추지 않음 (항상 종료 코드 0)
- 구글은 IndexNow 를 쓰지 않음 → 구글은 sitemap.xml 로 스스로 찾아감

키 파일: 사이트 맨 위의 9eeeaf1be380ad7c5356267a519e1bf9.txt (공개돼도 되는 키. 지우지 마세요)
"""
import json
import re
import sys
import time
import urllib.error
import urllib.request

KEY = '9eeeaf1be380ad7c5356267a519e1bf9'
HOST = 'ppaxse.com'
SITE = f'https://{HOST}'
ENDPOINT = 'https://searchadvisor.naver.com/indexnow'  # 네이버로 보내면 IndexNow 참여 검색엔진끼리 공유됨
URL_RE = re.compile(r'<url><loc>(.*?)</loc>(?:<lastmod>(.*?)</lastmod>)?</url>')


def read(path):
    try:
        return dict(URL_RE.findall(open(path, encoding='utf-8').read()))
    except FileNotFoundError:
        return {}


def live(url):
    try:
        req = urllib.request.Request(url, method='HEAD', headers={'User-Agent': 'ppaxse-indexnow'})
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status == 200
    except Exception:
        return False


def main():
    old, new = read(sys.argv[1]), read(sys.argv[2])
    changed = [u for u, lm in new.items() if u not in old or (lm and old.get(u) != lm)]
    if not changed:
        print('IndexNow: 새로 알릴 주소 없음')
        return
    print(f'IndexNow: 알릴 주소 {len(changed)}개')
    for u in changed:
        print('  ', u)

    # GitHub Pages 배포가 끝날 때까지 기다림 (키 파일 + 알릴 주소 모두 200 이 될 때까지, 최대 10분)
    check = [f'{SITE}/{KEY}.txt'] + changed
    for _ in range(40):
        waiting = [u for u in check if not live(u)]
        if not waiting:
            break
        time.sleep(15)
    else:
        print(f'IndexNow: 아직 안 열리는 주소 {len(waiting)}개 → 열린 주소만 보냄')
        changed = [u for u in changed if u not in waiting]
        if f'{SITE}/{KEY}.txt' in waiting or not changed:
            print('IndexNow: 보내지 않음 (키 파일이나 페이지가 아직 안 열림). 다음 실행 때 다시 시도되지 않으니 필요하면 직접 수집 요청')
            return

    body = json.dumps({'host': HOST, 'key': KEY, 'keyLocation': f'{SITE}/{KEY}.txt',
                       'urlList': changed[:10000]}).encode('utf-8')
    req = urllib.request.Request(ENDPOINT, data=body, method='POST',
                                 headers={'Content-Type': 'application/json; charset=utf-8'})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            print(f'IndexNow: 네이버 응답 {r.status} (200·202 = 접수됨)')
    except urllib.error.HTTPError as e:
        print(f'IndexNow: 네이버 응답 {e.code} {e.read()[:300]!r}')
    except Exception as e:
        print(f'IndexNow: 보내기 실패 {e}')


if __name__ == '__main__':
    try:
        main()
    except Exception as e:  # 알림 실패로 빌드를 멈추지 않음
        print(f'IndexNow: 오류 {e}')
