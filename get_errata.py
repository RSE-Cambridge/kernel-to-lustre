#!/usr/bin/env python3
import logging
import argparse
import requests
from datetime import datetime, timedelta
import sys, os, time
import re
import json
log = logging.getLogger(__name__)

#kernel-5.14.0-570.28.1.el9_6.src.rpm
kernel_regex = '''(kernel-)
(?P<major_revision>[0-9]+)(.)
(?P<minor_revision>[0-9]+)(.)
(?P<version>[0-9]+)(-)
(?P<patch_major_revision>[0-9]+)(.)
(?P<patch_minor_revision>[0-9]+)(.)
(?P<patch_version>[0-9]+)(.el)
(?P<el_major_version>[0-9]+)(_)
(?P<el_minor_version>[0-9]+)(.src.rpm)'''.replace('\n','')

kernel_format_string = "{kernel[2]}.{kernel[4]}.{kernel[6]}-{kernel[8]}.{kernel[10]}.{kernel[12]}"
el_format_string = "el{kernel[14]}_{kernel[16]}"

def _get(*local_args, max_attempts=10, **kwargs):
    '''Wrapper on requests to handle API rate limiting.'''
    global args
    done = False
    attempts=0
    while not done:
        headers = {'Authorization': f'Bearer {args.access_token}'}
        r = requests.get(*local_args, **kwargs, headers=headers)
        attempts += 1
        done = True
        if r.status_code in [200, 301, 302, 404]:
            return r
        elif r.status_code == 401: #Authentication required
            done = False
            args.access_token = get_access_token(args.token,token_url=args.token_url)
            log.info('API reauthentication required ...')
            time.sleep(1)
        elif r.status_code == 403: #Forbidden
            log.warning('Forbidden.')
            return None
        elif r.status_code == 429: #Rate limit exceeded
            done = False
            log.debug('API Rate limiting ...')
            time.sleep(5)
        elif r.status_code == 500: #Server error
            done = False
            log.debug('Server error ...')
            time.sleep(1)
        elif r.status_code == 504: #Gateway timeout
            done = False
            log.debug('Gateway time-out ...')
        else:
            log.warning(f'Unknown response: {r.status_code} {r.text}')
        if attempts >= max_attempts:
            log.debug('Max attempts reached.')
            return None
    return r

def get(url,params=None,page_size=100,max_count=float('inf')):
    '''Returns a page body contents.'''
    if params is None: params = {}
    params['limit'] = page_size
    params['offset'] = 0
    r = _get(url, params=params)
    if get(r,'status_code','') == 404:
        return None
    try:
        obj = r.json()
    except:
        return None
    end = False
    while not end:
        if 'body' not in obj:
            log.debug(f'no body: {obj}')
            yield obj
            break
        if type(obj['body']) is list:
            for e in obj['body']:
                yield e
        else:
            yield obj['body']
            break
        if 'pagination' in obj:
            params['offset'] += page_size
            if obj['pagination']['count'] < page_size: end = True
            if params['offset'] >= max_count: end = True
        else:
            end = True
        if not end:
            r = _get(url, params=params)
            obj = r.json()

def get_access_token(offline_token,token_url):
    '''Do the oath2 dance and get the current token.'''
    payload = {
        'grant_type': 'refresh_token',
        'client_id': 'rhsm-api',
        'refresh_token': offline_token,
    }
    r = requests.post(token_url, data=payload)
    token = json.loads(r.text)['access_token']
    if not token:
        raise RuntimeError('access_token call failed')
    return token

def check_errata(errata_id, api_base):
    '''True if real, false if 404'''
    ret = {}
    url = f'{api_base}/errata/{errata_id}'
    r = _get(url)
    return r.status_code in [200, 301, 302]

def yield_errata_from_contentsets(api_base,maj_el_ver,arch,cset_limit=1000,from_days=7,enabled_only=True):
    '''Ask for the contentsets from the relevant subscriptions, then find the errata from those.
Filter by age.'''
    now = datetime.now()
    subscriptions=set()
    url = f'{api_base}/subscriptions'
    for o in get(url,page_size=1000):
        if 'subscriptionNumber' in o:
            subscriptions.add(o['subscriptionNumber'])
    csets=set()
    for subscription in subscriptions:
        url = f'{api_base}/subscriptions/{subscription}/contentSets'
        for o in get(url,page_size=1000):
            cset=(o['label'],'noarch')
            if 'arch' in o:
                cset = (o['label'],o['arch'])
            if (
                f'rhel-{maj_el_ver}' in o['label'] or
               f'rhel{maj_el_ver}' in o['label']) and (
               arch in cset[1] or 'noarch' in cset[1]) and (
               not enabled_only or o['enabled']):
                csets.add(cset)
                log.info(f'CSET for {maj_el_ver}: {cset}')
    erratas=set()
    for cset in csets:
        url = f"{api_base}/errata/cset/{cset[0]}/arch/{cset[1]}"
        for o in get(url,page_size=1000,max_count=cset_limit):
            if 'advisoryId' in o:
                id = o['advisoryId']
                if 'RHSA' in id:
                    erratas.add(id)
    dated_errata = {}
    for errata in erratas:
       errata_date = get_errata_date(errata)
       if (now - errata_date).days <= from_days:
           log.info(f'Selected: {errata}')
           dated_errata[errata_date] = errata
    for date in sorted(list(dated_errata.keys()),reverse=True):
       yield dated_errata[date]

def get_errata_date(errata_id):
    '''Returns the most recent date an errata was published'''
    date=datetime(1970,1,1) #Epoch zero
    url = f'{api_base}/errata/{errata_id}'
    for obj in get(url):
        if 'issued' in obj:
            date = datetime.strptime(obj['issued'],'%Y-%m-%dT%H:%M:%S.000Z')
        if 'lastUpdated' in obj: #usually later...
            date = datetime.strptime(obj['lastUpdated'],'%Y-%m-%dT%H:%M:%S.000Z')
    return date

def yield_errata_source_packages(errata_id, api_base,maj_el_ver=None,min_el_ver=None):
    '''For a specific errata ID, see if this contains any kernels and filter if the el_ver are set.'''
    ret = {}
    url = f'{api_base}/errata/{errata_id}/packages'
    for pkg in get(url):
        logging.debug(f'file: {pkg["filename"]}')
        if 'arch' in pkg and pkg['arch'] == 'src' and re.match('kernel-[0-9]',pkg['filename']):
            if maj_el_ver != None:
                if f'.el{maj_el_ver}' not in pkg['filename']:
                    log.debug('fMajor version for {pkg["filename"]} not .el{maj_el_ver}')
                    continue
                if min_el_ver != None:
                    if f'.el{maj_el_ver}_{min_el_ver}' not in pkg['filename']:
                        log.info(f'Minor version for {pkg["filename"]} not .el{maj_el_ver}_{min_el_ver}')
                        continue
            yield pkg['filename'], pkg['checksum']

def fetch_package(filename, checksum, destination_path,api_base,force=False):
    '''Actually download the kernel file.'''
    url = f'{api_base}/packages/{checksum}/download'
    dest = f'{destination_path}/{filename}'
    if not os.path.exists(dest) or force:
        r = _get(url, stream=True)
        if r:
            with open(f'{destination_path}/{filename}','wb') as f:
                for n, chunk in enumerate(r.iter_content(chunk_size=1024)):
                    if n % 100 == 0:
                        log.debug(f'Saving chunk {n} ...')
                    f.write(chunk)
                kdata = re.match(kernel_regex,filename)
                kver = kernel_format_string.format(kernel=kdata)+'.'+el_format_string.format(kernel=kdata)
                print(kver)

def read_environ(e,default=None,func=None):
    '''Wrapper on os.environ with a default.'''
    ret = default
    if e in os.environ:
        ret = os.environ[e]
        if func is not None:
            ret = func(ret)
    return ret

def str2bool(s):
    if s.lower() in ['true','yes','y']: return True
    try:
        if float(s) != 0: return True
    except: pass
    return False

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('kernel_version', help='major kernel version to search.', type=int, choices=range(8,13))
    parser.add_argument('-m','--minor_kernel_version', help='minor kernel version to search.', type=int, choices=range(0,20))
    arch = read_environ('ERRATA_ARCH',default='x86_64')
    parser.add_argument('-a','--arch', help='architecture to select packages from', default=arch)
    cutoff = read_environ('ERRATA_CUTOFF',default=90,func=int)
    parser.add_argument('-c','--cutoff', help='cutoff in days to download in the past.', type=int, default=cutoff)
    force = read_environ('ERRATA_NO_DOWNLOAD',default=False,func=str2bool)
    parser.add_argument('-d','--no-download', help="Don't download files", action='store_true',default=force)
    force = read_environ('ERRATA_FORCE',default=False,func=str2bool)
    parser.add_argument('-f','--force', help='Overwrite existing files', action='store_true',default=force)
    dl_path = read_environ('ERRATA_TOKEN',func=str)
    parser.add_argument('-t','--token', help='Offline token for API.', default=dl_path)
    first_only = read_environ('ERRATA_FIRST_ONLY',default=True,func=str2bool)
    parser.add_argument('-1','--first-only', help='Return the first kernel only.', action='store_true',default=first_only)
    dl_path = read_environ('ERRATA_DOWNLOAD_PATH',default='.',func=str)
    parser.add_argument('-p','--download_path', help='path to download kernels to.', default=dl_path)
    token_url = read_environ('ERRATA_TOKEN_URL',default='https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token',func=str)
    parser.add_argument('-T','--token_url', help='OAuth path to get active token from.', default=token_url)
    api_base = read_environ('ERRATA_API_BASE',default='https://api.access.redhat.com/management/v1',func=str)
    parser.add_argument('-A','--api_base', help='API base URL.', default=api_base)
    verbose = read_environ('ERRATA_VERBOSE',default=False,func=str2bool)
    parser.add_argument('-v','--verbose', help='Be verbose.', action='store_true',default=verbose)
    args = parser.parse_args()
    if args.verbose:
        logging.basicConfig(stream=sys.stderr,level=logging.DEBUG)
    else:
        logging.basicConfig(stream=sys.stderr,level=logging.INFO)

    args.access_token = get_access_token(args.token,token_url=args.token_url)

    for errata in yield_errata_from_contentsets(api_base=args.api_base,maj_el_ver=args.kernel_version,arch=args.arch,from_days=args.cutoff,enabled_only=False):
        for f in yield_errata_source_packages(errata,maj_el_ver=args.kernel_version,min_el_ver=args.minor_kernel_version,api_base=args.api_base):
            log.info(f'Identified {f}')
            if args.no_download:
                log.warn(f'Not downloading {f} as requested.')
            else:
                fetch_package(f[0],f[1],'.',api_base=args.api_base,force=args.force)
            if args.first_only:
                exit()

