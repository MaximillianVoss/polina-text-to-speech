"""Safe standard-library companion for export-project.sh. Python 3.9+."""
import csv
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tarfile

GIT_NAMES = {'.git', '.github', '.gitmodules', '.gitconfig', '.git-credentials', '.git-credential-cache'}
GENERATED = {'node_modules', 'target', 'dist', 'build', 'coverage', '.expo', '.gradle', '.venv', 'venv', '__pycache__', '.DS_Store', '.idea', '.vscode', '.next', '.nuxt', '.cache', '.pytest_cache', '.mypy_cache'}
SECRET_NAMES = {'.npmrc', '.pypirc', '.netrc', '_netrc', '.ssh', '.aws', '.azure', '.kube', 'credentials.json', 'secrets.json', 'secrets.yaml', 'secrets.yml', 'id_rsa', 'id_ed25519'}
LOCAL_CONFIG = re.compile(r'^(application|appsettings)[-.](local|private|secrets)(?:\.|-).+', re.I)
DATABASE = re.compile(r'.*\.(?:db|sqlite|sqlite3|mv\.db|h2\.db|trace\.db)(?:-wal|-shm|-journal)?$', re.I)

def fail(message):
    raise ValueError(message)

def source_path(raw):
    if raw == '.':
        return raw
    if not raw or raw.startswith(('/', '-')) or '\\' in raw or ':' in raw or any(c in raw for c in '\n\r\t\x00'):
        fail('Нужен безопасный относительный --path.')
    if any(part in ('', '.', '..') for part in raw.split('/')):
        fail('--path не допускает пустые сегменты, . или ...')
    return raw

def destination(raw):
    if not raw or any(c in raw for c in '\n\r\t\x00') or '..' in Path(raw).parts:
        fail('Небезопасный путь назначения.')
    value = Path(os.path.abspath(raw))
    if value.name.lower() in ('', '.', '..', '.git') or value.name.endswith((' ', '.')):
        fail('Нужна отдельная папка назначения.')
    if not value.parent.is_dir():
        fail('Сначала создайте родительскую папку назначения.')
    value = value.parent.resolve() / value.name
    if value == Path.home().resolve() or value == Path.cwd().resolve() or value == Path('/'):
        fail('Домашняя, текущая и корневая папки не подходят для назначения.')
    if value.is_symlink():
        fail('Папка назначения не должна быть символической ссылкой.')
    if value.exists() and (not value.is_dir() or any(value.iterdir())):
        fail('Папка назначения уже существует и не пуста; ничего не изменено.')
    for ancestor in (value.parent, *value.parent.parents):
        metadata = ancestor / '.git'
        if os.path.lexists(metadata):
            fail('Назначение находится внутри другого Git-репозитория. Выберите независимую папку.')
    return value

def excluded(parts):
    for part in parts:
        lowered = part.lower()
        example = lowered.endswith(('.example', '.sample', '.template'))
        if lowered in GIT_NAMES or part in GENERATED or lowered in SECRET_NAMES or (not example and (DATABASE.fullmatch(part) or LOCAL_CONFIG.fullmatch(part) or lowered.endswith(('.key', '.pem', '.p12', '.pfx', '.jks', '.keystore')) or lowered.startswith('service-account'))):
            return True
        if part == '.env' or (part.startswith('.env.') and not example):
            return True
    return False

def check_credentials(path):
    """Refuse explicit credentials in unexpected JSON; never print their value.

    Application source, schemas and example templates are retained. This is a
    conservative delivery guard, not a general-purpose secret scanner.
    """
    if path.suffix.lower() != '.json' or path.name.lower().endswith(('.example', '.sample', '.template')):
        return
    try:
        value = json.loads(path.read_text(encoding='utf-8-sig'))
    except (UnicodeError, json.JSONDecodeError):
        return
    keys = {'private_key', 'privatekey', 'client_secret', 'access_token', 'refresh_token'}
    placeholders = {'', 'replace-me', 'replace_me', 'changeme', 'your-token', 'your_token', 'placeholder', 'example', 'null'}
    def visit(item):
        if isinstance(item, dict):
            for key, val in item.items():
                if str(key).lower() in keys and isinstance(val, str):
                    if val.lower().strip() not in placeholders and not val.startswith(('${', 'YOUR_', '<')):
                        fail('Обнаружено явное значение credential в JSON; экспорт отменён. Удалите его из исходного репозитория.')
                visit(val)
        elif isinstance(item, list):
            for val in item:
                visit(val)
    visit(value)

def extract(archive_path, target):
    target = Path(target)
    target.mkdir()
    with tarfile.open(archive_path, 'r:') as archive:
        members = archive.getmembers()
        # This marker identifies the optional upstream downloader bundled by
        # this delivery. Application folders with the same name are preserved.
        strip_tooling = any(item.name == 'delivery-tools/.upstream-tools' and item.isfile()
                            and item.size in (len(b'clean-export-tooling/v1\n'), len(b'clean-export-tooling/v1\r\n'))
                            and archive.extractfile(item).read() in (b'clean-export-tooling/v1\n', b'clean-export-tooling/v1\r\n')
                            for item in members)
        retained = []
        for item in members:
            name = PurePosixPath(item.name)
            if name.is_absolute() or '..' in name.parts or '\\' in item.name or ':' in item.name or any(c in item.name for c in '\r\n\t\x00'):
                fail('Архив содержит небезопасный путь.')
            if any(part.endswith((' ', '.')) or re.fullmatch(r'(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?', part, re.I) for part in name.parts):
                fail('Архив содержит непереносимое имя Windows.')
            if excluded(name.parts):
                continue
            if name.parts == ('.delivery-source.json',) or (strip_tooling and name.parts[0] == 'delivery-tools'):
                continue
            if not (item.isfile() or item.isdir() or item.issym()):
                fail('Архив содержит special file/hardlink; экспорт отменён.')
            if item.issym():
                # A portable delivery contains regular files only. No symlink
                # can recreate references to metadata, secrets or outside files.
                continue
            retained.append(item)
        # Do not extract below another archive entry that is a symlink.
        symlinks = {PurePosixPath(item.name) for item in members if item.issym()}
        for item in retained:
            if any(parent in symlinks for parent in PurePosixPath(item.name).parents):
                fail('Путь в архиве проходит через символическую ссылку.')
        for item in retained:
            out = target / item.name
            if item.isdir():
                out.mkdir(parents=True, exist_ok=True)
            else:
                out.parent.mkdir(parents=True, exist_ok=True)
                if item.issym():
                    out.symlink_to(item.linkname)
                else:
                    with archive.extractfile(item) as source, out.open('xb') as dest:
                        import shutil
                        shutil.copyfileobj(source, dest)
                    os.chmod(out, item.mode & 0o777)
                    check_credentials(out)
                    if out.name == 'README.md':
                        try:
                            text = out.read_text(encoding='utf-8')
                            cleaned = re.sub(r'\n?<!-- upstream-tools:start -->.*?<!-- upstream-tools:end -->\n?', '\n', text, flags=re.S)
                            if text != cleaned:
                                out.write_text(cleaned, encoding='utf-8')
                        except UnicodeError:
                            pass
                    if out.name == 'package.json':
                        try:
                            package = json.loads(out.read_text(encoding='utf-8'))
                            if isinstance(package, dict) and any(k in package for k in ('repository', 'homepage', 'bugs', 'funding')):
                                for key in ('repository', 'homepage', 'bugs', 'funding'):
                                    package.pop(key, None)
                                out.write_text(json.dumps(package, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
                        except (UnicodeError, json.JSONDecodeError):
                            pass
        if not any(target.iterdir()):
            fail('После исключения metadata проект пуст.')

def publish(payload, raw_destination, init_git):
    payload = Path(payload)
    final = destination(raw_destination)  # Recheck immediately before atomic rename.
    for entry in payload.rglob('*'):
        relative = entry.relative_to(payload)
        if entry.name in GIT_NAMES:
            if init_git and relative.parts == ('.git',):
                continue
            if init_git and relative.parts[0] == '.git':
                continue
            fail('В новой копии остались Git metadata.')
    # POSIX rename replaces an empty directory atomically. Windows requires
    # rmdir first: the kernel refuses it if any file appeared after validation.
    # A competing replacement folder then makes rename fail, never overwrite.
    removed_empty = False
    if os.name == 'nt' and final.exists():
        final.rmdir()
        removed_empty = True
    try:
        os.rename(payload, final)
    except OSError:
        if removed_empty and not final.exists():
            final.mkdir()
        raise

def catalog(filename, wanted=None):
    records = []
    seen = set()
    with open(filename, encoding='utf-8-sig', newline='') as f:
        for row in csv.reader(f, delimiter='\t', quoting=csv.QUOTE_NONE):
            if not row or row[0].startswith('#'):
                continue
            if row == ['id', 'repo', 'ref', 'path']:
                continue
            if len(row) != 4 or any(not part or any(c in part for c in '\n\r\x00') for part in row):
                fail('Каталог должен содержать 4 непустые колонки TAB.')
            if row[0] in seen:
                fail('Повторный id в каталоге.')
            seen.add(row[0])
            source_path(row[3])
            records.append(row)
    if wanted is None:
        print('\n'.join(row[0] for row in records))
    else:
        matches = [row for row in records if row[0] == wanted]
        if len(matches) != 1:
            fail('Не найден ровно один проект с таким id.')
        print('\t'.join(matches[0][1:]))

def main():
    mode, *args = sys.argv[1:]
    if mode == 'source-path':
        print(source_path(args[0]))
    elif mode == 'destination':
        # Bash/dirname must receive forward slashes even with native Windows
        # Python under Git Bash, so the temporary dir stays on the same volume.
        print(destination(args[0]).as_posix())
    elif mode == 'extract':
        extract(*args)
    elif mode == 'publish':
        publish(args[0], args[1], args[2] == '1')
    elif mode == 'catalog':
        catalog(*args)
    else:
        fail('Неизвестная операция.')

if __name__ == '__main__':
    # Native Windows Python under Git Bash must emit UTF-8 with LF. CRLF
    # would leave a trailing CR in Bash command substitutions and TSV fields.
    sys.stdout.reconfigure(encoding='utf-8', newline='\n')
    sys.stderr.reconfigure(encoding='utf-8', newline='\n')
    try:
        main()
    except (ValueError, OSError, tarfile.TarError) as error:
        print(f'Ошибка: {error}', file=sys.stderr)
        sys.exit(1)
