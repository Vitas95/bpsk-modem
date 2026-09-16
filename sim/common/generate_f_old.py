import os
import re
import sys
import platform
from pathlib import Path
from collections import defaultdict

# =============================================================================
# Конфигурация
# =============================================================================

SV_EXTENSIONS = {'.v', '.sv', '.vh', '.svh'}
INCLUDE_EXTENSIONS = {'.vh', '.svh'}

# Директории, которые никогда не нужно сканировать: система контроля версий,
# рабочие библиотеки симулятора (Questa/ModelSim создаёт work/, @_opt/, _opt/ и т.п.)
# Экономит время и убирает риск коллизий/переполнения длины пути на "мусорных" файлах.
EXCLUDE_DIR_NAMES = {'.git', '.svn', '.hg', '__pycache__', 'work'}


def is_excluded_dir(dirname: str) -> bool:
    if dirname in EXCLUDE_DIR_NAMES:
        return True
    # Артефакты Questa/ModelSim: _opt, @_opt, _lib и т.п.
    if dirname.startswith('_') or dirname.startswith('@'):
        return True
    return False


# -----------------------------------------------------------------------
# Windows: снятие ограничения MAX_PATH (260 символов).
# Без этого os.walk/open() могут молча "терять" файлы, лежащие глубоко
# во вложенных папках, если полный путь превышает лимит.
#
# ВАЖНО: этот префикс нужен ТОЛЬКО для файловых операций (open, os.walk).
# Для текстовых операций (os.path.relpath, print) всегда используем
# strip_long_prefix() — иначе os.path.relpath на Windows падает с
# "ValueError: path is on mount 'C:', start on mount '\\?\C:'",
# если одна сторона сравнения с префиксом, а другая без него.
# -----------------------------------------------------------------------
def long_path(p: Path) -> Path:
    if platform.system() != 'Windows':
        return p
    s = str(p)
    if s.startswith('\\\\?\\'):
        return p
    # UNC-пути (\\server\share\...) требуют префикса \\?\UNC\
    if s.startswith('\\\\'):
        return Path('\\\\?\\UNC\\' + s[2:])
    return Path('\\\\?\\' + s)


def strip_long_prefix(p: Path) -> Path:
    r"""Обратная операция к long_path() — убирает \\?\ / \\?\UNC\ префикс,
    чтобы путь можно было безопасно сравнивать с обычным (непрефиксованным)
    путём в os.path.relpath() и показывать пользователю в логах."""
    s = str(p)
    if s.startswith('\\\\?\\UNC\\'):
        return Path('\\\\' + s[8:])
    if s.startswith('\\\\?\\'):
        return Path(s[4:])
    return p


def rel(path: Path, start: Path) -> str:
    """Безопасный relpath: всегда сравнивает пути в одинаковой (непрефиксованной)
    форме, независимо от того, откуда они пришли."""
    return os.path.relpath(strip_long_prefix(path), strip_long_prefix(start)).replace('\\', '/')


# =============================================================================
# Сбор файлов проекта
# =============================================================================

def get_project_files(project_dir: Path):
    """
    Собирает все файлы с исходниками/инклудами внутри project_dir.

    В отличие от исходной версии, хранит СПИСОК путей на каждое имя файла,
    а не один путь — иначе одноимённые файлы в разных папках молча
    перезаписывали друг друга, и часть проекта пропадала из компиляции
    без единого предупреждения.
    """
    project_files: dict[str, list[Path]] = defaultdict(list)
    inc_dirs: set[Path] = set()

    scan_root = long_path(project_dir)

    for root, dirs, files in os.walk(scan_root, topdown=True):
        # Обрезаем ветки дерева прямо во время обхода — быстрее и безопаснее,
        # чем фильтровать результат постфактум.
        dirs[:] = [d for d in dirs if not is_excluded_dir(d)]

        for file in files:
            path = Path(root).resolve() / file
            if path.suffix in SV_EXTENSIONS:
                project_files[path.name].append(path)
                if path.suffix in INCLUDE_EXTENSIONS:
                    inc_dirs.add(path.parent.resolve())

    return project_files, inc_dirs


def report_name_collisions(project_files: dict[str, list[Path]]):
    """Явно предупреждает, если несколько файлов делят одно имя — раньше
    это приводило к тихой потере одного из них."""
    had_collisions = False
    for name, paths in sorted(project_files.items()):
        if len(paths) > 1:
            had_collisions = True
            print(f"   ПРЕДУПРЕЖДЕНИЕ: несколько файлов с именем '{name}':")
            for p in paths:
                print(f"      - {strip_long_prefix(p)}")
    if had_collisions:
        print("   (для include/instance-резолвинга по имени будет использован "
              "первый найденный файл — переименуйте дубликаты, если это не то, что нужно)")


# =============================================================================
# Парсинг зависимостей файла
# =============================================================================

KEYWORDS = {
    'module', 'endmodule', 'package', 'endpackage', 'interface', 'endinterface',
    'config', 'endconfig', 'generate', 'endgenerate', 'begin', 'end', 'assign',
    'always', 'always_ff', 'always_comb', 'always_latch', 'initial', 'final',
    'wire', 'reg', 'logic', 'bit', 'int', 'integer', 'input', 'output', 'inout',
    'parameter', 'localparam', 'typedef', 'function', 'endfunction', 'task',
    'endtask', 'class', 'endclass', 'if', 'else', 'case', 'casex', 'casez',
    'endcase', 'unique', 'priority', 'default', 'for', 'foreach', 'while', 'do',
    'forever', 'repeat', 'return', 'modport', 'import', 'export', 'posedge',
    'negedge', 'disable', 'fork', 'join', 'join_any', 'join_none', 'byte',
    'shortint', 'longint', 'real', 'string', 'event', 'chandle', 'rand', 'randc',
    'constraint', 'covergroup', 'coverpoint', 'cross', 'property', 'sequence',
    'endproperty', 'endsequence', 'program', 'endprogram', 'extern', 'pure',
    'local', 'protected', 'this', 'null', 'new', 'super', 'void', 'static',
    'automatic', 'const', 'virtual', 'extends', 'signed', 'unsigned', 'genvar',
}

# Строки-директивы препроцессора (`define, `ifdef, `include и т.п.) не должны
# попадать в поиск инстансов — иначе имя макроса или условие компиляции может
# ложно распознаться как "тип модуля". `include обрабатывается отдельно выше,
# остальное просто вырезаем (вместе с продолжениями строк через '\').
def strip_directive_lines(content: str) -> str:
    lines = content.split('\n')
    out = []
    skip_continuation = False
    for line in lines:
        stripped = line.strip()
        if skip_continuation:
            out.append('')
            skip_continuation = stripped.endswith('\\')
            continue
        if stripped.startswith('`'):
            out.append('')
            skip_continuation = stripped.endswith('\\')
            continue
        out.append(line)
    return '\n'.join(out)

INCLUDE_RE = re.compile(r'^\s*`include\s+"([^"]+)"')
IMPORT_RE = re.compile(r'\bimport\s+(\w+)::')
DEFINITION_RE = re.compile(r'\b(module|package|interface)\s+([a-zA-Z_]\w*)')
IDENT_RE = re.compile(r'[a-zA-Z_]\w*')

_WS = ' \t\r\n'


def _skip_ws(s: str, i: int) -> int:
    n = len(s)
    while i < n and s[i] in _WS:
        i += 1
    return i


def _match_balanced_parens(s: str, i: int):
    """s[i] должен быть '('. Возвращает индекс сразу ПОСЛЕ соответствующей
    закрывающей ')', корректно учитывая вложенные скобки (например,
    вызовы функций вида $size(...) внутри списка параметров инстанса)."""
    assert s[i] == '('
    depth = 1
    i += 1
    n = len(s)
    while i < n and depth > 0:
        if s[i] == '(':
            depth += 1
        elif s[i] == ')':
            depth -= 1
        i += 1
    return i


def extract_instances(content: str) -> set[str]:
    """
    Находит инстансы вида:
        module_type instance_name (...)
        module_type #( ... ) instance_name (...)
    Скобки параметров разбираются вручную со счётчиком глубины —
    это надёжнее ленивой regex-жадности на выражениях с вложенными
    скобками (например, $size(...) внутри #(...)).
    """
    deps: set[str] = set()
    n = len(content)
    i = 0
    while i < n:
        m = IDENT_RE.match(content, i)
        if not m:
            i += 1
            continue
        word = m.group(0)
        j = m.end()

        if word in KEYWORDS:
            i = j
            continue

        k = _skip_ws(content, j)

        # Вариант 1: word #( ... ) instance_name (
        if k < n and content[k] == '#':
            p = _skip_ws(content, k + 1)
            if p < n and content[p] == '(':
                p = _match_balanced_parens(content, p)
                p = _skip_ws(content, p)
                m2 = IDENT_RE.match(content, p)
                if m2 and m2.group(0) not in KEYWORDS:
                    q = _skip_ws(content, m2.end())
                    if q < n and content[q] == '(':
                        deps.add(word)
                        i = m2.end()
                        continue

        # Вариант 2: word instance_name (   (без параметров)
        elif k < n and (content[k].isalpha() or content[k] == '_'):
            m2 = IDENT_RE.match(content, k)
            # Важно проверить, что и второе слово — не ключевое: иначе
            # "begin : SomeLabel" перед "if (...)"/"for (...)" ложно
            # распознаётся как инстанс типа "SomeLabel" с именем "if"/"for".
            if m2 and m2.group(0) not in KEYWORDS:
                q = _skip_ws(content, m2.end())
                if q < n and content[q] == '(':
                    deps.add(word)
                    i = m2.end()
                    continue

        i = j
    return deps


def parse_file_content(file_path: Path):
    modules_defined: set[str] = set()
    dependencies: set[str] = set()

    try:
        with open(long_path(file_path), 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        print(f"   ОШИБКА чтения файла {file_path}: {e}")
        return modules_defined, dependencies

    content = re.sub(r'//.*', '', content)
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)

    for line in content.splitlines():
        inc_match = INCLUDE_RE.match(line)
        if inc_match:
            dependencies.add(inc_match.group(1))

    for pkg in IMPORT_RE.findall(content):
        dependencies.add(pkg)

    # `include уже собран выше; для поиска определений модулей и инстансов
    # убираем строки-директивы, чтобы не ловить ложные срабатывания вида
    # "`define FOO(...)" или "`ifdef BAR".
    content_for_scan = strip_directive_lines(content)

    for match in DEFINITION_RE.finditer(content_for_scan):
        modules_defined.add(match.group(2))

    dependencies |= extract_instances(content_for_scan)

    return modules_defined, dependencies


def map_project(project_files: dict[str, list[Path]]):
    """Строит карту 'символ (module/package/interface/имя файла) -> файл'."""
    mod_to_file: dict[str, Path] = {}
    file_deps: dict[Path, set[str]] = {}
    all_paths = [p for paths in project_files.values() for p in paths]

    for file_path in all_paths:
        mods, deps = parse_file_content(file_path)
        file_deps[file_path] = deps
        for mod in mods:
            if mod in mod_to_file and mod_to_file[mod] != file_path:
                print(f"   ПРЕДУПРЕЖДЕНИЕ: '{mod}' определён и в "
                      f"{strip_long_prefix(mod_to_file[mod])}, и в {strip_long_prefix(file_path)} — используется первый")
                continue
            mod_to_file[mod] = file_path

    # Резолвинг по имени файла (для `include) — только если символ с таким
    # именем ещё не определён; при коллизии имён файлов берём первый найденный.
    for name, paths in project_files.items():
        mod_to_file.setdefault(name, paths[0])

    return mod_to_file, file_deps


# =============================================================================
# Построение порядка компиляции
# =============================================================================

def resolve_dependencies(start_file_path: Path, mod_to_file, file_deps):
    ordered_files: list[Path] = []
    visited: set[Path] = set()
    visiting: set[Path] = set()
    unresolved: set[str] = set()

    def dfs(file_path: Path):
        if file_path in visiting or file_path in visited:
            return
        visiting.add(file_path)

        for dep in file_deps.get(file_path, []):
            dep_name = Path(dep).name
            dep_file_path = mod_to_file.get(dep_name) or mod_to_file.get(dep)

            if dep_file_path and dep_file_path.exists():
                dfs(dep_file_path)
            else:
                unresolved.add(dep)

        visiting.discard(file_path)
        visited.add(file_path)
        if file_path not in ordered_files:
            ordered_files.append(file_path)

    dfs(start_file_path)
    return ordered_files, unresolved


# =============================================================================
# main
# =============================================================================

def main():
    if len(sys.argv) < 3:
        print("Использование: python generate_f.py <путь_к_папке_проекта> <имя_top_файла.sv>")
        sys.exit(1)

    project_dir = Path(sys.argv[1]).resolve()
    top_file_name = sys.argv[2]
    current_working_dir = Path.cwd().resolve()

    if not project_dir.exists() or not project_dir.is_dir():
        print(f"Ошибка: Папка проекта '{strip_long_prefix(project_dir)}' не существует.")
        sys.exit(1)

    print(f"1. Текущая папка запуска: {strip_long_prefix(current_working_dir)}")
    print(f"2. Сканирование папки проекта: {strip_long_prefix(project_dir)}")
    project_files, inc_dirs = get_project_files(project_dir)
    print(f"   Найдено файлов: {sum(len(v) for v in project_files.values())}")
    report_name_collisions(project_files)

    if top_file_name not in project_files:
        print(f"Ошибка: Файл '{top_file_name}' не найден внутри папки проекта.")
        sys.exit(1)

    target_file_path = project_files[top_file_name][0]

    print("3. Глубокий анализ кода и связей модулей...")
    mod_to_file, file_deps = map_project(project_files)

    print("4. Рекурсивное построение дерева компиляции (снизу вверх)...")
    file_list, unresolved = resolve_dependencies(target_file_path, mod_to_file, file_deps)

    if unresolved:
        print("   ПРЕДУПРЕЖДЕНИЕ: не удалось найти файлы для следующих зависимостей "
              "(проверь опечатки в именах модулей/`include или что файл вообще есть в project_dir):")
        for u in sorted(unresolved):
            print(f"      - {u}")

    output_f_name = f"{Path(top_file_name).stem}.f"
    output_f_file = current_working_dir / output_f_name

    with open(output_f_file, 'w', encoding='utf-8') as f:
        f.write("// Автоматически сгенерировано для QuestaSim\n")
        f.write(f"// Все пути указаны ОТНОСИТЕЛЬНО этой папки запуска: {strip_long_prefix(current_working_dir)}\n\n")

        f.write("+libext+.v+.sv+.vh+.svh\n\n")

        f.write("// Директории include (относительно папки запуска):\n")
        rel_proj_str = rel(project_dir, current_working_dir)
        f.write(f"+incdir+{rel_proj_str}\n")

        for inc_path in sorted(inc_dirs):
            f.write(f"+incdir+{rel(inc_path, current_working_dir)}\n")

        f.write("\n// Порядок компиляции файлов (относительно папки запуска):\n")
        for file_path in file_list:
            f.write(f"{rel(file_path, current_working_dir)}\n")

    print(f"\nУспешно! Создан конфигурационный файл ({len(file_list)} файлов):\n{strip_long_prefix(output_f_file)}")
    if unresolved:
        print(f"НО есть {len(unresolved)} нерезолвленных зависимостей — см. предупреждения выше.")
        sys.exit(2)


if __name__ == "__main__":
    main()