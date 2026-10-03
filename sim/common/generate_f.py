import os
import re
import sys
import platform
from pathlib import Path
from collections import defaultdict

# =============================================================================
# Configuration
# =============================================================================

SV_EXTENSIONS = {'.v', '.sv', '.vh', '.svh'}
INCLUDE_EXTENSIONS = {'.vh', '.svh'}

# Directories that should never be scanned: version control, simulator work
# libraries (Questa/ModelSim creates work/, @_opt/, _opt/, etc.). This saves
# time and avoids the risk of collisions / path-length overflow on "junk"
# files.
EXCLUDE_DIR_NAMES = {'.git', '.svn', '.hg', '__pycache__', 'work'}


def is_excluded_dir(dirname: str) -> bool:
    if dirname in EXCLUDE_DIR_NAMES:
        return True
    # Questa/ModelSim artifacts: _opt, @_opt, _lib, etc.
    if dirname.startswith('_') or dirname.startswith('@'):
        return True
    return False


# -----------------------------------------------------------------------
# Windows: lifting the MAX_PATH (260 character) limit.
# Without this, os.walk/open() can silently "lose" files that live deep
# inside nested folders once the full path exceeds the limit.
#
# IMPORTANT: this prefix is needed ONLY for filesystem operations (open,
# os.walk). For text operations (os.path.relpath, print) we always use
# strip_long_prefix() instead — otherwise os.path.relpath on Windows fails
# with "ValueError: path is on mount 'C:', start on mount '\\?\C:'" when
# one side of the comparison has the prefix and the other doesn't.
# -----------------------------------------------------------------------
def long_path(p: Path) -> Path:
    if platform.system() != 'Windows':
        return p
    s = str(p)
    if s.startswith('\\\\?\\'):
        return p
    # UNC paths (\\server\share\...) require the \\?\UNC\ prefix.
    if s.startswith('\\\\'):
        return Path('\\\\?\\UNC\\' + s[2:])
    return Path('\\\\?\\' + s)


def strip_long_prefix(p: Path) -> Path:
    r"""Inverse of long_path() — removes the \\?\ / \\?\UNC\ prefix so the
    path can be safely compared against a regular (unprefixed) path in
    os.path.relpath() and shown to the user in logs."""
    s = str(p)
    if s.startswith('\\\\?\\UNC\\'):
        return Path('\\\\' + s[8:])
    if s.startswith('\\\\?\\'):
        return Path(s[4:])
    return p


def rel(path: Path, start: Path) -> str:
    """Safe relpath: always compares paths in the same (unprefixed) form,
    regardless of where they came from."""
    return os.path.relpath(strip_long_prefix(path), strip_long_prefix(start)).replace('\\', '/')


# =============================================================================
# Collecting project files
# =============================================================================

def get_project_files(project_dir: Path):
    """
    Collects all source/include files inside project_dir.

    Unlike the original version, this stores a LIST of paths for each file
    name instead of a single path — otherwise files that share a name but
    live in different folders would silently overwrite each other, and part
    of the project would disappear from the compilation without any warning.
    """
    project_files: dict[str, list[Path]] = defaultdict(list)
    inc_dirs: set[Path] = set()

    scan_root = long_path(project_dir)

    for root, dirs, files in os.walk(scan_root, topdown=True):
        # Prune tree branches during the walk itself — faster and safer than
        # filtering the result after the fact.
        dirs[:] = [d for d in dirs if not is_excluded_dir(d)]

        for file in files:
            path = Path(root).resolve() / file
            if path.suffix in SV_EXTENSIONS:
                project_files[path.name].append(path)
                if path.suffix in INCLUDE_EXTENSIONS:
                    inc_dirs.add(path.parent.resolve())

    return project_files, inc_dirs


def report_name_collisions(project_files: dict[str, list[Path]]):
    """Explicitly warns if several files share the same name — previously
    this led to one of them being silently dropped."""
    had_collisions = False
    for name, paths in sorted(project_files.items()):
        if len(paths) > 1:
            had_collisions = True
            print(f"   WARNING: multiple files named '{name}':")
            for p in paths:
                print(f"      - {strip_long_prefix(p)}")
    if had_collisions:
        print("   (the first file found will be used for include/instance "
              "resolution by name — rename the duplicates if that's not what you want)")


# =============================================================================
# Parsing file dependencies
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

# Preprocessor directive lines (`define, `ifdef, `include, etc.) must not
# leak into the instance search — otherwise a macro name or a compilation
# guard could be falsely recognized as a "module type". `include is handled
# separately above; everything else is simply cut out (along with its
# line continuations via a trailing '\').
#
# A multi-line `define (continued via a trailing backslash) is a special
# case: its BODY often contains a real module instantiation (e.g. a macro
# that wraps "comb #(...) instance_name (...)" for repeated use across a
# file). Only the directive's header line is blanked; continuation lines
# are kept so instantiations inside macro bodies are still detected.
# Backtick token-paste sequences inside those lines (like ``name``, used
# to build instance/signal names from macro arguments, e.g.
# "``name``" -> "name") are stripped so the instantiation regex can match
# straight through them.
def strip_directive_lines(content: str) -> str:
    lines = content.split('\n')
    out = []
    skip_continuation = False
    for line in lines:
        stripped = line.strip()
        if skip_continuation:
            # Continuation line of a multi-line directive (most commonly the
            # body of a `define): keep it for instantiation scanning, just
            # strip the backtick token-paste markers.
            out.append(line.replace('`', ''))
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
# A package can also be used without an explicit `import pkg::*;` — simply
# through scope resolution like `pkg::symbol` (e.g. in a port or type
# declaration: `bpsk_tx_pkg::tx_state_t state`). IMPORT_RE doesn't catch
# this, which meant the dependency on the package was "lost" for files that
# use it this way instead of via import — and the package file could end up
# in the .f AFTER the file that uses it. PKG_SCOPE_RE catches any
# "identifier::" reference.
PKG_SCOPE_RE = re.compile(r'\b([a-zA-Z_]\w*)\s*::')
DEFINITION_RE = re.compile(r'\b(module|package|interface)\s+([a-zA-Z_]\w*)')
IDENT_RE = re.compile(r'[a-zA-Z_]\w*')

_WS = ' \t\r\n'


def _skip_ws(s: str, i: int) -> int:
    n = len(s)
    while i < n and s[i] in _WS:
        i += 1
    return i


def _match_balanced_parens(s: str, i: int):
    """s[i] must be '('. Returns the index right AFTER the matching closing
    ')', correctly accounting for nested parentheses (e.g. function calls
    like $size(...) inside an instance's parameter list)."""
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
    Finds instantiations of the form:
        module_type instance_name (...)
        module_type #( ... ) instance_name (...)
    The parameter parentheses are parsed manually with a depth counter —
    this is more reliable than lazy regex greediness on expressions with
    nested parentheses (e.g. $size(...) inside #(...)).
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

        # Variant 1: word #( ... ) instance_name (
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

        # Variant 2: word instance_name (   (no parameters)
        elif k < n and (content[k].isalpha() or content[k] == '_'):
            m2 = IDENT_RE.match(content, k)
            # It's important to also check that the second word isn't a
            # keyword: otherwise "begin : SomeLabel" before "if (...)"/
            # "for (...)" would be falsely recognized as an instance of
            # type "SomeLabel" named "if"/"for".
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
        print(f"   ERROR reading file {file_path}: {e}")
        return modules_defined, dependencies

    content = re.sub(r'//.*', '', content)
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)

    for line in content.splitlines():
        inc_match = INCLUDE_RE.match(line)
        if inc_match:
            dependencies.add(inc_match.group(1))

    for pkg in IMPORT_RE.findall(content):
        dependencies.add(pkg)

    # `include has already been collected above; for finding module
    # definitions, instances and package scope references, we strip
    # directive lines so we don't pick up false positives like
    # "`define FOO(...)" or "`ifdef BAR".
    content_for_scan = strip_directive_lines(content)

    for match in DEFINITION_RE.finditer(content_for_scan):
        modules_defined.add(match.group(2))

    # References to a package like `pkg::symbol` without an explicit import
    # (e.g. in a port type declaration) are also a dependency, and must be
    # accounted for — otherwise the package file could end up in the
    # compilation list after the file that uses it.
    for pkg in PKG_SCOPE_RE.findall(content_for_scan):
        if pkg not in KEYWORDS:
            dependencies.add(pkg)

    dependencies |= extract_instances(content_for_scan)

    return modules_defined, dependencies


def map_project(project_files: dict[str, list[Path]]):
    """Builds a map of 'symbol (module/package/interface/file name) -> file'."""
    mod_to_file: dict[str, Path] = {}
    file_deps: dict[Path, set[str]] = {}
    all_paths = [p for paths in project_files.values() for p in paths]

    for file_path in all_paths:
        mods, deps = parse_file_content(file_path)
        file_deps[file_path] = deps
        for mod in mods:
            if mod in mod_to_file and mod_to_file[mod] != file_path:
                print(f"   WARNING: '{mod}' is defined both in "
                      f"{strip_long_prefix(mod_to_file[mod])} and in {strip_long_prefix(file_path)} — using the first one")
                continue
            mod_to_file[mod] = file_path

    # Resolution by file name (for `include) — only if a symbol with that
    # name isn't already defined; on a file name collision, the first file
    # found is used.
    for name, paths in project_files.items():
        mod_to_file.setdefault(name, paths[0])

    return mod_to_file, file_deps


# =============================================================================
# Building the compilation order
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
        print("Usage: python generate_f.py <path_to_project_folder> <top_file_name.sv>")
        sys.exit(1)

    project_dir = Path(sys.argv[1]).resolve()
    top_file_name = sys.argv[2]
    current_working_dir = Path.cwd().resolve()

    if not project_dir.exists() or not project_dir.is_dir():
        print(f"Error: project folder '{strip_long_prefix(project_dir)}' does not exist.")
        sys.exit(1)

    print(f"1. Current working directory: {strip_long_prefix(current_working_dir)}")
    print(f"2. Scanning project folder: {strip_long_prefix(project_dir)}")
    project_files, inc_dirs = get_project_files(project_dir)
    print(f"   Files found: {sum(len(v) for v in project_files.values())}")
    report_name_collisions(project_files)

    if top_file_name not in project_files:
        print(f"Error: file '{top_file_name}' not found inside the project folder.")
        sys.exit(1)

    target_file_path = project_files[top_file_name][0]

    print("3. Deep analysis of code and module relationships...")
    mod_to_file, file_deps = map_project(project_files)

    print("4. Recursively building the compilation tree (bottom-up)...")
    file_list, unresolved = resolve_dependencies(target_file_path, mod_to_file, file_deps)

    if unresolved:
        print("   WARNING: could not find files for the following dependencies "
              "(check for typos in module names/`include, or that the file even exists in project_dir):")
        for u in sorted(unresolved):
            print(f"      - {u}")

    output_f_name = f"{Path(top_file_name).stem}.f"
    output_f_file = current_working_dir / output_f_name

    with open(output_f_file, 'w', encoding='utf-8') as f:
        f.write("// Auto-generated for QuestaSim\n")
        f.write(f"// All paths are RELATIVE to this working directory: {strip_long_prefix(current_working_dir)}\n\n")

        f.write("+libext+.v+.sv+.vh+.svh\n\n")

        f.write("// Include directories (relative to the working directory):\n")
        rel_proj_str = rel(project_dir, current_working_dir)
        f.write(f"+incdir+{rel_proj_str}\n")

        for inc_path in sorted(inc_dirs):
            f.write(f"+incdir+{rel(inc_path, current_working_dir)}\n")

        f.write("\n// File compilation order (relative to the working directory):\n")
        for file_path in file_list:
            f.write(f"{rel(file_path, current_working_dir)}\n")

    print(f"\nSuccess! Config file created ({len(file_list)} files):\n{strip_long_prefix(output_f_file)}")
    if unresolved:
        print(f"BUT there are {len(unresolved)} unresolved dependencies — see the warnings above.")
        sys.exit(2)


if __name__ == "__main__":
    main()