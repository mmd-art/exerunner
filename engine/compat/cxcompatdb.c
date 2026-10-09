/* win-runner's compat module.
 *
 * ntdll dlopens <dir of ntdll.so>/cxcompatdb.so at the end of process start-up, before the main
 * executable runs (CrossOver hack 24067 in dlls/ntdll/unix/loader.c), and exports
 * prepend_dll_path() and add_load_order_override() for it. CrossOver ships a closed module under
 * that name which applies its compatibility database. This one applies what the launcher
 * (scripts/run.sh) puts in the environment:
 *
 *   WINRUNNER_D3DMETAL_DIR   D3DMetal's wine/ dir (x86_64-windows, x86_64-unix). Prepended to the
 *                            builtin DLL search path, so its d3d10/d3d11/d3d12/dxgi replace wine's
 *                            own in this process only.
 *   WINRUNNER_D3DMETAL_SKIP  comma-separated executable names that keep wine's own DLLs, such as
 *                            steamwebhelper.exe, whose Chromium crashes on D3DMetal's D3D11. Read
 *                            only without a compat file (run.sh); the app says it in the file.
 *   WINRUNNER_COMPAT_FILE    lines "<program.exe>\tNAME=value"; the matching ones are set in this
 *                            process. That reaches a game a launcher starts, which inherits the
 *                            launcher's environment otherwise. Only libraries reading the Unix
 *                            environment see them (D3DMetal, Metal, MoltenVK): the Windows
 *                            environment, which DXVK reads, was built before this runs.
 *                            "<program.exe>\t@d3dmetal=off" keeps that program on wine's own DLLs.
 *                            The app rewrites the file before each launch, so a launcher started
 *                            earlier still hands its games current settings.
 *
 * By the time this runs, wine has rewritten argv: argv[0] is the Windows path of the executable.
 *
 * build: clang -arch x86_64 -dynamiclib -O2 -o cxcompatdb.so cxcompatdb.c
 */
#include <crt_externs.h>
#include <dlfcn.h>
#include <libgen.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

static const char *exe_name(void)
{
    char **argv = *_NSGetArgv();
    const char *name, *p;

    if (!argv || !argv[0]) return NULL;
    name = argv[0];
    for (p = name; *p; p++) if (*p == '\\' || *p == '/') name = p + 1;
    return name;
}

static int in_list(const char *name, const char *list)
{
    size_t len;

    if (!name || !list) return 0;
    len = strlen(name);
    while (*list)
    {
        const char *end = strchr(list, ',');
        size_t n = end ? (size_t)(end - list) : strlen(list);

        if (n == len && !strncasecmp(list, name, n)) return 1;
        if (!end) break;
        list = end + 1;
    }
    return 0;
}

/* ntdll.so normally sits in the global namespace; if not, open it next to this module */
static void *ntdll_symbol(const char *symbol)
{
    char path[PATH_MAX], dir[PATH_MAX];
    void *sym, *ntdll;
    Dl_info info;

    if ((sym = dlsym(RTLD_DEFAULT, symbol))) return sym;
    if (!dladdr((void *)ntdll_symbol, &info) || !info.dli_fname) return NULL;
    snprintf(dir, sizeof(dir), "%s", info.dli_fname);
    snprintf(path, sizeof(path), "%s/ntdll.so", dirname(dir));
    if (!(ntdll = dlopen(path, RTLD_NOLOAD | RTLD_LAZY))) return NULL;
    return dlsym(ntdll, symbol);
}

/* Applies this program's lines from WINRUNNER_COMPAT_FILE. Returns -1 without a readable file,
 * else 1 when a line turns D3DMetal off for the program and 0 when none does. */
static int apply_compat_file(const char *exe)
{
    const char *path = getenv("WINRUNNER_COMPAT_FILE");
    char line[4096];
    int d3dmetal_off = 0;
    FILE *file;

    if (!exe || !path || !*path || !(file = fopen(path, "r"))) return -1;
    while (fgets(line, sizeof(line), file))
    {
        char *tab = strchr(line, '\t'), *eq, *end;

        if (!tab) continue;
        *tab = 0;
        if (strcasecmp(line, exe)) continue;
        if ((end = strpbrk(tab + 1, "\r\n"))) *end = 0;
        if (!(eq = strchr(tab + 1, '=')) || eq == tab + 1) continue;
        *eq = 0;
        if (!strcmp(tab + 1, "@d3dmetal")) d3dmetal_off = !strcmp(eq + 1, "off");
        else setenv(tab + 1, eq + 1, 1);
    }
    fclose(file);
    return d3dmetal_off;
}

__attribute__((constructor))
static void winrunner_compat_init(void)
{
    const char *dir;
    void (*prepend_dll_path)(const char *);
    char *copy;
    int d3dmetal_off = apply_compat_file(exe_name());

    dir = getenv("WINRUNNER_D3DMETAL_DIR");
    if (!dir || !*dir || d3dmetal_off == 1) return;
    /* the file is rewritten before every launch; a list inherited from a launcher may be older */
    if (d3dmetal_off == -1 && in_list(exe_name(), getenv("WINRUNNER_D3DMETAL_SKIP"))) return;
    if (!(prepend_dll_path = ntdll_symbol("prepend_dll_path"))) return;
    /* the loader keeps the pointer for the life of the process */
    if ((copy = strdup(dir))) prepend_dll_path(copy);
}
