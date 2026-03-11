#!/usr/bin/env bash
# Сборка DXVK, VKD3D-Proton, DXVK-NVAPI для использования с текущим деревом Wine
# (боевая сборка по аналогии с GE-Proton, без Docker).
# Собирает и 64-бит (x64), и 32-бит (x32) варианты при наличии i686-w64-mingw32-gcc.
#
# Требования: meson, ninja; MinGW (x86_64 и при необходимости i686) — из системы,
#              или скачивается с musl.cc, или собирается из исходников (--build-mingw-from-source).
# Запуск из корня дерева Wine: ./tools/build-full-wine-deps.sh [опции]
# Самодостаточная сборка: Wine — из нашего дерева (если собран), нативные lib — с системы (gstreamer, vulkan и т.д.).
# Опции: --build-mingw-from-source; --no-install-wine; --no-bundle-system-libs; --copy-native-from=DIR; --only-mingw; --force-rebuild; --no-wine-icu (не ставить wine-icu под системную libicu); --no-wine-mono (не собирать локальный wine-mono).
# По завершении создаётся дистрибутив в подпапке dist: $WINE_ROOT/dist/$DIST_NAME. Подробнее: README.md

set -e

BUILD_MINGW_FROM_SOURCE=0
INSTALL_WINE=1
BUNDLE_SYSTEM_LIBS=1
COPY_NATIVE_FROM=""
ONLY_MINGW=0
FORCE_REBUILD_DEPS=0
WITH_WINE_ICU=1
WITH_WINE_MONO=1
while [ "$#" -gt 0 ]; do
    case "$1" in
        --build-mingw-from-source) BUILD_MINGW_FROM_SOURCE=1 ;;
        --no-install-wine)         INSTALL_WINE=0 ;;
        --no-bundle-system-libs)   BUNDLE_SYSTEM_LIBS=0 ;;
        --copy-native-from=*)      COPY_NATIVE_FROM="${1#--copy-native-from=}"; BUNDLE_SYSTEM_LIBS=0 ;;
        --copy-native-from)
            [ -n "${2:-}" ] && COPY_NATIVE_FROM="$2" && shift && BUNDLE_SYSTEM_LIBS=0 || { echo "Требуется аргумент для --copy-native-from" >&2; exit 1; }
            ;;
        --only-mingw)             ONLY_MINGW=1 ;;
        --force-rebuild)          FORCE_REBUILD_DEPS=1 ;;
        --no-wine-icu)            WITH_WINE_ICU=0 ;;
        --no-wine-mono)           WITH_WINE_MONO=0 ;;
        *) echo "Неизвестный аргумент: $1. См. заголовок скрипта или README.md." >&2; exit 1 ;;
    esac
    shift
done

WINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS_DIR="$WINE_ROOT/build-deps"
DIST_DIR="$DEPS_DIR/dist"
BUILD_DIR="$DEPS_DIR/build"
MINGW_CROSS_DIR="$DEPS_DIR/x86_64-w64-mingw32-cross"
MINGW32_CROSS_DIR="$DEPS_DIR/i686-w64-mingw32-cross"
MINGW_BUILD_ROOT="$DEPS_DIR/mingw-build"
MINGW32_BUILD_ROOT="$DEPS_DIR/mingw-build32"

mkdir -p "$DEPS_DIR" "$DIST_DIR" "$DIST_DIR/x64" "$DIST_DIR/x32"
cd "$DEPS_DIR"

# Пропуск пересборки: если репозиторий не менялся и все нужные DLL уже есть в DIST_DIR.
# Используется сохранённый git rev в $DEPS_DIR/.<name>-rev. Сброс: --force-rebuild или удаление .*-rev.

# Проверка обновлений в upstream: fetch и сравнение с сохранённым rev; при отличии — сброс .*-rev для пересборки.
check_deps_upstream() {
    local repo_dir rev_file name
    for spec in "dxvk:.dxvk-rev" "vkd3d-proton:.vkd3d-rev" "dxvk-nvapi:.nvapi-rev"; do
        name="${spec%%:*}"
        rev_file="$DEPS_DIR/${spec#*:}"
        repo_dir="$DEPS_DIR/$name"
        [ ! -d "$repo_dir/.git" ] && continue
        [ ! -f "$rev_file" ] && continue
        (cd "$repo_dir" && git fetch --quiet 2>/dev/null) || true
        origin_ref=$(git -C "$repo_dir" rev-parse refs/remotes/origin/HEAD 2>/dev/null) || \
        origin_ref=$(git -C "$repo_dir" rev-parse origin/master 2>/dev/null) || \
        origin_ref=$(git -C "$repo_dir" rev-parse origin/main 2>/dev/null) || true
        [ -z "$origin_ref" ] && continue
        saved=$(cat "$rev_file" 2>/dev/null | tr -d '\n\r')
        [ -z "$saved" ] && continue
        if [ "$saved" != "$origin_ref" ]; then
            echo "Обнаружены обновления в $name (upstream), будет пересборка."
            rm -f "$rev_file"
        fi
    done
}

need_deps_build() {
    local rev_file="$1" repo_dir="$2"
    shift 2
    local required_dlls=("$@")
    [ "$FORCE_REBUILD_DEPS" -eq 1 ] && return 0
    [ ! -d "$repo_dir" ] && return 0
    local current_rev=""
    current_rev=$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null) || return 0
    [ -z "$current_rev" ] && return 0
    if [ -f "$rev_file" ] && [ "$(cat "$rev_file" | tr -d '\n\r')" = "$current_rev" ]; then
        for f in "${required_dlls[@]}"; do
            [ -f "$f" ] || return 0
        done
        return 1
    fi
    return 0
}
save_deps_rev() { echo "$(git -C "$2" rev-parse HEAD 2>/dev/null)" > "$1"; }

check_command() {
    if ! command -v "$1" &>/dev/null; then
        echo "Ошибка: не найден $1. Установите пакеты (meson, ninja, glslang, vulkan-headers и т.д.)." >&2
        exit 1
    fi
}
check_command meson
check_command ninja

# Поиск MinGW: 1) система, 2) уже скачанный/собранный в build-deps, 3) скачать с musl.cc, 4) собрать из исходников
MINGW_BIN=""
if command -v x86_64-w64-mingw32-gcc &>/dev/null; then
    MINGW_BIN="$(dirname "$(command -v x86_64-w64-mingw32-gcc)")"
elif command -v mingw64-gcc &>/dev/null; then
    MINGW_BIN="$(dirname "$(command -v mingw64-gcc)")"
fi

if [ -z "$MINGW_BIN" ] && [ -x "$MINGW_CROSS_DIR/bin/x86_64-w64-mingw32-gcc" ]; then
    MINGW_BIN="$MINGW_CROSS_DIR/bin"
fi

if [ -z "$MINGW_BIN" ] && [ -x "$DEPS_DIR/mingw64-cross/bin/x86_64-w64-mingw32-gcc" ]; then
    MINGW_BIN="$DEPS_DIR/mingw64-cross/bin"
fi

if [ -n "$MINGW_BIN" ]; then
    export PATH="$MINGW_BIN:$PATH"
    echo "Используется MinGW: $MINGW_BIN/x86_64-w64-mingw32-gcc"
else
    if [ "$BUILD_MINGW_FROM_SOURCE" -eq 1 ]; then
        MINGW_DEPS="gcc g++ make bison flex git makeinfo m4 bzip2 curl diff"
        MISSING=""
        for ex in $MINGW_DEPS; do
            if ! command -v "$ex" &>/dev/null; then MISSING="$MISSING $ex"; fi
        done
        if [ -n "$MISSING" ]; then
            echo "Ошибка: для сборки MinGW из исходников нужны:$MISSING" >&2
            echo "  makeinfo — пакет texinfo (apt install texinfo / dnf install texinfo)." >&2
            exit 1
        fi
        echo "Сборка MinGW-w64 из исходников (30–60 мин)..."
        if [ ! -d "$DEPS_DIR/mingw-w64-build" ]; then
            git clone --depth 1 https://github.com/Zeranoe/mingw-w64-build.git "$DEPS_DIR/mingw-w64-build"
        fi
        mkdir -p "$MINGW_BUILD_ROOT"
        if [ ! -x "$DEPS_DIR/mingw64-cross/bin/x86_64-w64-mingw32-gcc" ] || [ ! -x "$DEPS_DIR/mingw64-cross/bin/i686-w64-mingw32-gcc" ]; then
            "$DEPS_DIR/mingw-w64-build/mingw-w64-build" x86_64 i686 \
                -r "$MINGW_BUILD_ROOT" \
                -p "$DEPS_DIR/mingw64-cross" \
                -j "$(nproc 2>/dev/null || echo 2)" \
                || { echo "Сборка MinGW из исходников не удалась. См. $MINGW_BUILD_ROOT/build.log" >&2; exit 1; }
        fi
        MINGW_BIN="$DEPS_DIR/mingw64-cross/bin"
        export PATH="$MINGW_BIN:$PATH"
        echo "Используется собранный MinGW: $MINGW_BIN"
    else
        echo "MinGW не найден. Скачиваю пресобранный кросс-компилятор с musl.cc (~130 МБ)..."
        MINGW_TGZ="$DEPS_DIR/x86_64-w64-mingw32-cross.tgz"
        if [ ! -f "$MINGW_TGZ" ]; then
            (cd "$DEPS_DIR" && curl -fL -o x86_64-w64-mingw32-cross.tgz "https://musl.cc/x86_64-w64-mingw32-cross.tgz") \
                || (cd "$DEPS_DIR" && wget -O x86_64-w64-mingw32-cross.tgz "https://musl.cc/x86_64-w64-mingw32-cross.tgz") \
                || { echo "Не удалось скачать MinGW. Проверьте сеть или используйте --build-mingw-from-source для сборки из исходников." >&2; exit 1; }
        fi
        if [ ! -x "$MINGW_CROSS_DIR/bin/x86_64-w64-mingw32-gcc" ]; then
            (cd "$DEPS_DIR" && tar -xzf x86_64-w64-mingw32-cross.tgz) \
                || { echo "Распаковка MinGW не удалась." >&2; exit 1; }
        fi
        [ -x "$MINGW_CROSS_DIR/bin/x86_64-w64-mingw32-gcc" ] || { echo "После распаковки не найден $MINGW_CROSS_DIR/bin/x86_64-w64-mingw32-gcc" >&2; exit 1; }
        export PATH="$MINGW_CROSS_DIR/bin:$PATH"
        echo "Используется MinGW из musl.cc: $MINGW_CROSS_DIR/bin"
    fi
fi

# 32-битный MinGW (i686): приоритет 1) Zeranoe (оба в mingw64-cross), 2) Zeranoe i686 (mingw32-cross), 3) сборка i686 из исходников, 4) musl.cc
if ! command -v i686-w64-mingw32-gcc &>/dev/null; then
    if [ -x "$DEPS_DIR/mingw64-cross/bin/i686-w64-mingw32-gcc" ]; then
        : # уже в PATH (Zeranoe собрал оба арха)
    elif [ -x "$DEPS_DIR/mingw32-cross/bin/i686-w64-mingw32-gcc" ]; then
        export PATH="$DEPS_DIR/mingw32-cross/bin:$PATH"
        echo "Используется MinGW 32-bit (из исходников): $DEPS_DIR/mingw32-cross/bin"
    else
        # Сборка i686 из исходников (Zeranoe) — GCC 15, совместимо с DXVK; приоритет выше musl.cc (GCC 11)
        MINGW_DEPS="gcc g++ make bison flex git makeinfo m4 bzip2 curl diff"
        CAN_BUILD=1
        for ex in $MINGW_DEPS; do
            if ! command -v "$ex" &>/dev/null; then CAN_BUILD=0; break; fi
        done
        if [ "$CAN_BUILD" -eq 1 ]; then
            echo "Сборка MinGW 32-bit (i686) из исходников (20–40 мин)..."
            if [ ! -d "$DEPS_DIR/mingw-w64-build" ]; then
                git clone --depth 1 https://github.com/Zeranoe/mingw-w64-build.git "$DEPS_DIR/mingw-w64-build"
            fi
            mkdir -p "$MINGW32_BUILD_ROOT"
            if [ ! -x "$DEPS_DIR/mingw32-cross/bin/i686-w64-mingw32-gcc" ]; then
                if "$DEPS_DIR/mingw-w64-build/mingw-w64-build" i686 \
                    -r "$MINGW32_BUILD_ROOT" \
                    -p "$DEPS_DIR/mingw32-cross" \
                    -j "$(nproc 2>/dev/null || echo 2)"; then
                    export PATH="$DEPS_DIR/mingw32-cross/bin:$PATH"
                    echo "Используется MinGW 32-bit (собран): $DEPS_DIR/mingw32-cross/bin"
                else
                    echo "Сборка MinGW 32-bit не удалась. См. $MINGW32_BUILD_ROOT/build.log" >&2
                    CAN_BUILD=0
                fi
            else
                export PATH="$DEPS_DIR/mingw32-cross/bin:$PATH"
                echo "Используется MinGW 32-bit: $DEPS_DIR/mingw32-cross/bin"
            fi
        fi
        if [ "$CAN_BUILD" -eq 0 ] || ! command -v i686-w64-mingw32-gcc &>/dev/null; then
            if [ -x "$MINGW32_CROSS_DIR/bin/i686-w64-mingw32-gcc" ]; then
                export PATH="$MINGW32_CROSS_DIR/bin:$PATH"
                echo "Используется MinGW 32-bit (musl.cc, GCC 11; для DXVK x32 может не собраться): $MINGW32_CROSS_DIR/bin"
            else
                echo "Скачиваю MinGW 32-bit с musl.cc (~130 МБ, GCC 11; для DXVK предпочтительна сборка из исходников)..."
                MINGW32_TGZ="$DEPS_DIR/i686-w64-mingw32-cross.tgz"
                if [ ! -f "$MINGW32_TGZ" ]; then
                    (cd "$DEPS_DIR" && curl -fL -o i686-w64-mingw32-cross.tgz "https://musl.cc/i686-w64-mingw32-cross.tgz") \
                        || (cd "$DEPS_DIR" && wget -O i686-w64-mingw32-cross.tgz "https://musl.cc/i686-w64-mingw32-cross.tgz") \
                        || { echo "Не удалось скачать MinGW 32-bit. Сборка x32 будет пропущена." >&2; MINGW32_OK=0; }
                fi
                if [ "${MINGW32_OK:-1}" != "0" ] && [ ! -x "$MINGW32_CROSS_DIR/bin/i686-w64-mingw32-gcc" ]; then
                    (cd "$DEPS_DIR" && tar -xzf i686-w64-mingw32-cross.tgz) || true
                    [ -x "$MINGW32_CROSS_DIR/bin/i686-w64-mingw32-gcc" ] && export PATH="$MINGW32_CROSS_DIR/bin:$PATH" && echo "Используется MinGW 32-bit (musl.cc): $MINGW32_CROSS_DIR/bin"
                fi
            fi
        fi
    fi
fi
BUILD_32=0
if command -v i686-w64-mingw32-gcc &>/dev/null; then BUILD_32=1; fi

# Режим --only-mingw: только подготовить MinGW и выйти (для полного пайплайна full-build.sh)
if [ "$ONLY_MINGW" -eq 1 ]; then
    echo "export PATH=\"$PATH\"" > "$DEPS_DIR/.mingw-path"
    echo "MinGW готов. PATH записан в $DEPS_DIR/.mingw-path"
    exit 0
fi

# Если 32-бит из Zeranoe (mingw32-cross), сбрасываем кэш meson для x32 (пути к компилятору могли измениться)
if [ "$BUILD_32" -eq 1 ] && [ -x "$DEPS_DIR/mingw32-cross/bin/i686-w64-mingw32-gcc" ]; then
    for d in "$BUILD_DIR/dxvk32" "$BUILD_DIR/vkd3d32" "$BUILD_DIR/nvapi32"; do
        [ -d "$d" ] && rm -rf "$d"
    done
fi

# Проверить upstream: при наличии новых коммитов сбросить .*-rev, чтобы пересобрать.
check_deps_upstream

# --- DXVK ---
if [ ! -d dxvk ]; then
    echo "Клонирование DXVK..."
    git clone --depth 1 https://github.com/doitsujin/dxvk.git
fi
mkdir -p "$DIST_DIR/x64"
dxvk_dlls=( "$DIST_DIR/x64/dxgi.dll" "$DIST_DIR/x64/d3d11.dll" "$DIST_DIR/x64/d3d10core.dll" "$DIST_DIR/x64/d3d9.dll" "$DIST_DIR/x64/d3d8.dll" )
[ "$BUILD_32" -eq 1 ] && dxvk_dlls+=( "$DIST_DIR/x32/dxgi.dll" "$DIST_DIR/x32/d3d11.dll" "$DIST_DIR/x32/d3d10core.dll" "$DIST_DIR/x32/d3d9.dll" "$DIST_DIR/x32/d3d8.dll" )
if need_deps_build "$DEPS_DIR/.dxvk-rev" "$DEPS_DIR/dxvk" "${dxvk_dlls[@]}"; then
    cd dxvk
    git fetch --depth 1 origin 2>/dev/null || true
    git reset --hard refs/remotes/origin/HEAD 2>/dev/null || git pull --depth 1 2>/dev/null || true
    git submodule update --init --recursive
    echo "Сборка DXVK (x64)..."
    if [ -f build-win64.txt ]; then
        if meson setup --cross-file build-win64.txt --buildtype release --prefix="$DIST_DIR" --bindir=x64 --libdir=x64 -Db_ndebug=if-release "$BUILD_DIR/dxvk64"; then
            ninja -C "$BUILD_DIR/dxvk64" install
        fi
    fi
    for d in "$BUILD_DIR/dxvk64" build.x64; do
        [ -d "$d" ] || continue
        for f in "$d"/src/*/*.dll "$d"/x64/*.dll; do
            [ -f "$f" ] && cp -n "$f" "$DIST_DIR/x64/" 2>/dev/null || true
        done
    done
    if [ "$BUILD_32" -eq 1 ] && [ -f build-win32.txt ]; then
        echo "Сборка DXVK (x32)..."
        if meson setup --cross-file build-win32.txt --buildtype release --prefix="$DIST_DIR" --bindir=x32 --libdir=x32 -Db_ndebug=if-release "$BUILD_DIR/dxvk32"; then
            ninja -C "$BUILD_DIR/dxvk32" install
        fi
        for d in "$BUILD_DIR/dxvk32" build.x32; do
            [ -d "$d" ] || continue
            for f in "$d"/src/*/*.dll "$d"/x32/*.dll; do
                [ -f "$f" ] && cp -n "$f" "$DIST_DIR/x32/" 2>/dev/null || true
            done
        done
    fi
    save_deps_rev "$DEPS_DIR/.dxvk-rev" "$DEPS_DIR/dxvk"
    cd "$DEPS_DIR"
else
    echo "DXVK уже собран (без изменений), пропуск."
fi

# VKD3D-Proton требует widl (из дерева Wine). Обёртка в PATH под именами *-widl.
WIDL_BIN="$WINE_ROOT/tools/widl/widl"
WIDL_WRAPPER_DIR="$DEPS_DIR/widl-wrapper"
if [ -x "$WIDL_BIN" ]; then
    mkdir -p "$WIDL_WRAPPER_DIR"
    for name in x86_64-w64-mingw32-widl i686-w64-mingw32-widl; do
        [ -x "$WIDL_WRAPPER_DIR/$name" ] || ln -sf "$WIDL_BIN" "$WIDL_WRAPPER_DIR/$name"
    done
    export PATH="$WIDL_WRAPPER_DIR:$PATH"
    echo "Используется widl из дерева Wine: $WIDL_BIN"
elif ! command -v x86_64-w64-mingw32-widl &>/dev/null && ! command -v widl &>/dev/null; then
    echo "Предупреждение: widl не найден (ни в дереве Wine $WIDL_BIN, ни в PATH). Соберите Wine (make -C tools/widl) или установите wine-tools. Сборка VKD3D может упасть." >&2
fi

# --- VKD3D-Proton ---
if [ ! -d vkd3d-proton ]; then
    echo "Клонирование VKD3D-Proton..."
    git clone --depth 1 https://github.com/HansKristian-Work/vkd3d-proton.git
fi
vkd3d_dlls=( "$DIST_DIR/x64/d3d12.dll" "$DIST_DIR/x64/d3d12core.dll" )
[ "$BUILD_32" -eq 1 ] && vkd3d_dlls+=( "$DIST_DIR/x32/d3d12.dll" "$DIST_DIR/x32/d3d12core.dll" )
if need_deps_build "$DEPS_DIR/.vkd3d-rev" "$DEPS_DIR/vkd3d-proton" "${vkd3d_dlls[@]}"; then
    cd vkd3d-proton
    git fetch --depth 1 origin 2>/dev/null || true
    git reset --hard refs/remotes/origin/HEAD 2>/dev/null || git pull --depth 1 2>/dev/null || true
    git submodule update --init --recursive
    echo "Сборка VKD3D-Proton (x64)..."
    if [ -f build-win64.txt ]; then
        if meson setup --cross-file build-win64.txt --buildtype release --prefix="$DIST_DIR" --bindir=x64 --libdir=x64 -Db_ndebug=if-release "$BUILD_DIR/vkd3d64"; then
            ninja -C "$BUILD_DIR/vkd3d64" install
        fi
    fi
    for d in "$BUILD_DIR/vkd3d64" build; do
        [ -d "$d" ] || continue
        for f in "$d"/src/*.dll "$d"/x64/*.dll; do
            [ -f "$f" ] && cp -n "$f" "$DIST_DIR/x64/" 2>/dev/null || true
        done
    done
    if [ "$BUILD_32" -eq 1 ] && [ -f build-win32.txt ]; then
        echo "Сборка VKD3D-Proton (x32)..."
        if meson setup --cross-file build-win32.txt --buildtype release --prefix="$DIST_DIR" --bindir=x32 --libdir=x32 -Db_ndebug=if-release "$BUILD_DIR/vkd3d32"; then
            ninja -C "$BUILD_DIR/vkd3d32" install
        fi
        for d in "$BUILD_DIR/vkd3d32" build; do
            [ -d "$d" ] || continue
            for f in "$d"/src/*.dll "$d"/x32/*.dll; do
                [ -f "$f" ] && cp -n "$f" "$DIST_DIR/x32/" 2>/dev/null || true
            done
        done
    fi
    save_deps_rev "$DEPS_DIR/.vkd3d-rev" "$DEPS_DIR/vkd3d-proton"
    cd "$DEPS_DIR"
else
    echo "VKD3D-Proton уже собран (без изменений), пропуск."
fi

# --- DXVK-NVAPI ---
if [ ! -d dxvk-nvapi ]; then
    echo "Клонирование DXVK-NVAPI..."
    git clone --depth 1 https://github.com/jp7677/dxvk-nvapi.git
fi
nvapi_dlls=( "$DIST_DIR/x64/nvapi64.dll" "$DIST_DIR/x64/nvofapi64.dll" )
[ "$BUILD_32" -eq 1 ] && nvapi_dlls+=( "$DIST_DIR/x32/nvapi.dll" )
if need_deps_build "$DEPS_DIR/.nvapi-rev" "$DEPS_DIR/dxvk-nvapi" "${nvapi_dlls[@]}"; then
    cd dxvk-nvapi
    git fetch --depth 1 origin 2>/dev/null || true
    git reset --hard refs/remotes/origin/HEAD 2>/dev/null || git pull --depth 1 2>/dev/null || true
    git submodule update --init --recursive
    echo "Сборка DXVK-NVAPI (x64)..."
    if [ -f build-win64.txt ]; then
        if meson setup --cross-file build-win64.txt --buildtype release --prefix="$DIST_DIR" --bindir=x64 --libdir=x64 -Db_ndebug=if-release "$BUILD_DIR/nvapi64"; then
            ninja -C "$BUILD_DIR/nvapi64" install
        fi
    fi
    for d in "$BUILD_DIR/nvapi64" build; do
        [ -d "$d" ] || continue
        for f in "$d"/src/*.dll "$d"/x64/*.dll; do
            [ -f "$f" ] && cp -n "$f" "$DIST_DIR/x64/" 2>/dev/null || true
        done
    done
    if [ "$BUILD_32" -eq 1 ] && [ -f build-win32.txt ]; then
        echo "Сборка DXVK-NVAPI (x32)..."
        if meson setup --cross-file build-win32.txt --buildtype release --prefix="$DIST_DIR" --bindir=x32 --libdir=x32 -Db_ndebug=if-release "$BUILD_DIR/nvapi32"; then
            ninja -C "$BUILD_DIR/nvapi32" install
        fi
        for d in "$BUILD_DIR/nvapi32" build; do
            [ -d "$d" ] || continue
            for f in "$d"/src/*.dll "$d"/x32/*.dll; do
                [ -f "$f" ] && cp -n "$f" "$DIST_DIR/x32/" 2>/dev/null || true
            done
        done
    fi
    save_deps_rev "$DEPS_DIR/.nvapi-rev" "$DEPS_DIR/dxvk-nvapi"
    cd "$DEPS_DIR"
else
    echo "DXVK-NVAPI уже собран (без изменений), пропуск."
fi

echo ""
echo "Готово. Результат в: $DIST_DIR"
echo "  x64: $DIST_DIR/x64/ → \$WINEPREFIX/drive_c/windows/system32/"
echo "  x32: $DIST_DIR/x32/ → \$WINEPREFIX/drive_c/windows/syswow64/"
echo "Либо задайте WINEDLLOVERRIDES=dxgi=n,b;d3d11=n,b;d3d10core=n,b;d3d9=n,b и добавьте соответствующий каталог в PATH при запуске wine."

# --- Дистрибутив в формате PortProton / GE-Proton ---
DIST_NAME="${DIST_NAME:-WINE-BLEEDING-$(date +%d%m%Y)}"
OUT_DIST="$WINE_ROOT/dist/$DIST_NAME"
mkdir -p "$OUT_DIST/bin" "$OUT_DIST/bin-wow64" "$OUT_DIST/share"
# Каталог для нативных lib — создаём сразу, чтобы был даже при раннем выходе (наполнится в блоке ниже)
[ "$BUNDLE_SYSTEM_LIBS" -eq 1 ] && mkdir -p "$OUT_DIST/lib/$(uname -m)-linux-gnu"
ln -sfn lib/wine "$OUT_DIST/lib64" 2>/dev/null || (rm -f "$OUT_DIST/lib64" 2>/dev/null; ln -sfn lib/wine "$OUT_DIST/lib64")

if [ "$INSTALL_WINE" -eq 1 ]; then
    if [ -f "$WINE_ROOT/Makefile" ] && [ -x "$WINE_ROOT/loader/wine" ] && [ -x "$WINE_ROOT/server/wineserver" ]; then
        echo "Установка Wine из дерева в дистрибутив ($OUT_DIST)..."
        # Если Makefile настроен на clang, а объектники собраны под MinGW — make install пересобирает и падает (lld/SEH).
        # Переконфигурируем с MinGW и пересобираем, чтобы install не вызывал несовместимую линковку.
        if [ -n "$MINGW_BIN" ] && grep -q 'i386_CC = clang' "$WINE_ROOT/Makefile" 2>/dev/null; then
            echo "Makefile использует clang; переконфигурация с MinGW и пересборка..."
            (cd "$WINE_ROOT" && export PATH="$MINGW_BIN:$PATH" && ./tools/configure-wine-full.sh) || true
            if ! make -C "$WINE_ROOT" -j"$(nproc)"; then
                echo "Ошибка пересборки Wine. Выполните вручную:" >&2
                echo "  export PATH=\"$MINGW_BIN:\$PATH\" && cd $WINE_ROOT && ./tools/configure-wine-full.sh && make -j\$(nproc)" >&2
                exit 1
            fi
        fi
        make -C "$WINE_ROOT" install prefix="$OUT_DIST" DESTDIR=""
        # Раскладка в стиле GE-Proton: bin-wow64 не оставляем пустым — лаунчер wine (32-бит в WoW64)
        if [ -x "$OUT_DIST/bin/wine" ] && [ -d "$OUT_DIST/bin-wow64" ]; then
            ln -sfn ../bin/wine "$OUT_DIST/bin-wow64/wine" 2>/dev/null || cp -n "$OUT_DIST/bin/wine" "$OUT_DIST/bin-wow64/wine" 2>/dev/null || true
        fi
    else
        echo "Wine в дереве не собран — пропуск установки (соберите: ./configure --enable-win64 && make). Создаю заглушки." >&2
        mkdir -p "$OUT_DIST/lib/wine/i386-unix" "$OUT_DIST/lib/wine/x86_64-unix" \
                 "$OUT_DIST/lib/wine/i386-windows" "$OUT_DIST/lib/wine/x86_64-windows" \
                 "$OUT_DIST/lib/wine/icu/i386-windows" "$OUT_DIST/lib/wine/icu/x86_64-windows"
    fi
else
    mkdir -p "$OUT_DIST/lib/wine/i386-unix" "$OUT_DIST/lib/wine/x86_64-unix" \
             "$OUT_DIST/lib/wine/i386-windows" "$OUT_DIST/lib/wine/x86_64-windows" \
             "$OUT_DIST/lib/wine/icu/i386-windows" "$OUT_DIST/lib/wine/icu/x86_64-windows"
fi

mkdir -p "$OUT_DIST/lib/wine/dxvk/x86_64-windows" "$OUT_DIST/lib/wine/dxvk/i386-windows"
mkdir -p "$OUT_DIST/lib/wine/vkd3d-proton/x86_64-windows" "$OUT_DIST/lib/wine/vkd3d-proton/i386-windows"
mkdir -p "$OUT_DIST/lib/wine/nvapi/x86_64-windows" "$OUT_DIST/lib/wine/nvapi/i386-windows"
# lib/vkd3d/ не создаём: мы собираем только VKD3D-Proton (d3d12/d3d12core); libvkd3d-1.dll — из отдельного проекта vkd3d (WineHQ), его нет в сборке

# Копируем только .dll (без .a). cp -n не перезаписывает; || true чтобы не падать при set -e.
for f in "$DIST_DIR/x64"/d3d8.dll "$DIST_DIR/x64"/d3d9.dll "$DIST_DIR/x64"/d3d10core.dll "$DIST_DIR/x64"/d3d11.dll "$DIST_DIR/x64"/dxgi.dll; do
    [ -f "$f" ] && cp -n "$f" "$OUT_DIST/lib/wine/dxvk/x86_64-windows/" 2>/dev/null || true
done
for f in "$DIST_DIR/x32"/d3d8.dll "$DIST_DIR/x32"/d3d9.dll "$DIST_DIR/x32"/d3d10core.dll "$DIST_DIR/x32"/d3d11.dll "$DIST_DIR/x32"/dxgi.dll; do
    [ -f "$f" ] && cp -n "$f" "$OUT_DIST/lib/wine/dxvk/i386-windows/" 2>/dev/null || true
done
for f in "$DIST_DIR/x64"/d3d12.dll "$DIST_DIR/x64"/d3d12core.dll; do
    [ -f "$f" ] && cp -n "$f" "$OUT_DIST/lib/wine/vkd3d-proton/x86_64-windows/" 2>/dev/null || true
done
for f in "$DIST_DIR/x32"/d3d12.dll "$DIST_DIR/x32"/d3d12core.dll; do
    [ -f "$f" ] && cp -n "$f" "$OUT_DIST/lib/wine/vkd3d-proton/i386-windows/" 2>/dev/null || true
done
for f in "$DIST_DIR/x64"/nvapi64.dll "$DIST_DIR/x64"/nvofapi64.dll; do
    [ -f "$f" ] && cp -n "$f" "$OUT_DIST/lib/wine/nvapi/x86_64-windows/" 2>/dev/null || true
done
for f in "$DIST_DIR/x32"/nvapi.dll; do
    [ -f "$f" ] && cp -n "$f" "$OUT_DIST/lib/wine/nvapi/i386-windows/" 2>/dev/null || true
done

# Файлы version (как в GE-Proton)
echo "$(date +%s) $DIST_NAME" > "$OUT_DIST/version"
[ -d "$DEPS_DIR/dxvk/.git" ] && echo "$(git -C "$DEPS_DIR/dxvk" rev-parse HEAD) dxvk ($(git -C "$DEPS_DIR/dxvk" describe --tags 2>/dev/null || git -C "$DEPS_DIR/dxvk" rev-parse --short HEAD))" > "$OUT_DIST/lib/wine/dxvk/version" || echo "dxvk (local)" > "$OUT_DIST/lib/wine/dxvk/version"
[ -d "$DEPS_DIR/vkd3d-proton/.git" ] && echo "$(git -C "$DEPS_DIR/vkd3d-proton" rev-parse HEAD) vkd3d-proton ($(git -C "$DEPS_DIR/vkd3d-proton" describe --tags 2>/dev/null || git -C "$DEPS_DIR/vkd3d-proton" rev-parse --short HEAD))" > "$OUT_DIST/lib/wine/vkd3d-proton/version" || echo "vkd3d-proton (local)" > "$OUT_DIST/lib/wine/vkd3d-proton/version"
[ -d "$DEPS_DIR/dxvk-nvapi/.git" ] && echo "$(git -C "$DEPS_DIR/dxvk-nvapi" rev-parse HEAD) dxvk-nvapi ($(git -C "$DEPS_DIR/dxvk-nvapi" describe --tags 2>/dev/null || git -C "$DEPS_DIR/dxvk-nvapi" rev-parse --short HEAD))" > "$OUT_DIST/lib/wine/nvapi/version" || echo "dxvk-nvapi (local)" > "$OUT_DIST/lib/wine/nvapi/version"

# Нативные библиотеки: с системы (по умолчанию) или из каталога (--copy-native-from)
if [ -n "$COPY_NATIVE_FROM" ]; then
    if [ -d "$COPY_NATIVE_FROM/lib/i386-linux-gnu" ] || [ -d "$COPY_NATIVE_FROM/lib/x86_64-linux-gnu" ]; then
        echo "Копирование нативных lib из $COPY_NATIVE_FROM..."
        for sub in i386-linux-gnu x86_64-linux-gnu; do
            [ -d "$COPY_NATIVE_FROM/lib/$sub" ] && cp -a "$COPY_NATIVE_FROM/lib/$sub" "$OUT_DIST/lib/"
        done
    else
        echo "Предупреждение: в $COPY_NATIVE_FROM не найдены lib/i386-linux-gnu или lib/x86_64-linux-gnu." >&2
    fi
elif [ "$BUNDLE_SYSTEM_LIBS" -eq 1 ]; then
    ARCH_LIB="$(uname -m)-linux-gnu"
    SYS_NATIVE="$OUT_DIST/lib/$ARCH_LIB"
    mkdir -p "$SYS_NATIVE"
    # Список библиотек, нужных для Wine/медиа (ищем в ldconfig, копируем из системы)
    SYSTEM_LIBS="libvulkan libgstreamer-1.0 libgstbase-1.0 libgstapp-1.0 libgstaudio-1.0 libgstvideo-1.0 libgstpbutils-1.0 libavcodec libavformat libavutil libavfilter libdav1d libxkbcommon libgraphene-1.0 libglib-2.0 libgobject-2.0 libffi"
    echo "Копирование нативных lib с системы в $SYS_NATIVE..."
    for lib in $SYSTEM_LIBS; do
        path=""
        [ -z "$path" ] && path=$(ldconfig -p 2>/dev/null | grep -E "[[:space:]]${lib}\.so" | head -1 | sed 's/.*=>[[:space:]]*//') || true
        [ -z "$path" ] && path=$(ldconfig -p 2>/dev/null | grep "$lib" | head -1 | sed 's/.*=>[[:space:]]*//') || true
        [ -z "$path" ] && [ -d "/usr/lib/$ARCH_LIB" ] && path=$(find "/usr/lib/$ARCH_LIB" -maxdepth 1 -name "${lib}.so*" -type f 2>/dev/null | head -1) || true
        [ -z "$path" ] && path=$(find /usr/lib64 /lib64 /usr/lib /lib -maxdepth 1 -name "${lib}.so*" -type f 2>/dev/null | head -1) || true
        [ -n "$path" ] && [ -f "$path" ] || continue
        dir=$(dirname "$path")
        for f in "$dir"/${lib}.so*; do
            [ -e "$f" ] && cp -an "$f" "$SYS_NATIVE/" 2>/dev/null || true
        done
    done
    # Копируем плагины gstreamer-1.0 из стандартного каталога, если есть
    for gstdir in /usr/lib/"$ARCH_LIB"/gstreamer-1.0 /usr/lib/gstreamer-1.0; do
        [ -d "$gstdir" ] && { cp -an "$gstdir" "$SYS_NATIVE/" 2>/dev/null && break; } || true
    done
fi

echo ""
echo "Дистрибутив (формат PortProton): $OUT_DIST"
echo "  (можно подложить в PortProton или использовать lib/wine поверх существующего Wine.)"
echo "  Структура: bin/ и bin-wow64/ — исполняемые; lib64 — симлинк на lib/wine; D3D12 — lib/wine/vkd3d-proton/."
[ -f "$WINE_ROOT/Makefile" ] && [ -x "$WINE_ROOT/loader/wine" ] && [ "$INSTALL_WINE" -eq 1 ] && echo "  Wine установлен из дерева (bin, lib/wine, share); bin-wow64 заполнен лаунчером." || true
if [ "$BUNDLE_SYSTEM_LIBS" -eq 1 ] && [ -z "$COPY_NATIVE_FROM" ]; then
    NATIVE_DIR="$OUT_DIST/lib/$(uname -m)-linux-gnu"
    if [ -d "$NATIVE_DIR" ]; then
        n=$(find "$NATIVE_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
        [ "$n" -gt 0 ] && echo "  Нативные lib скопированы с системы в lib/$(uname -m)-linux-gnu/ ($n файлов)."
        [ "$n" -eq 0 ] && echo "  Каталог lib/$(uname -m)-linux-gnu/ создан, но пуст (ldconfig/библиотеки не найдены?)." >&2 || true
    fi
fi
[ -n "$COPY_NATIVE_FROM" ] && echo "  Нативные lib взяты из $COPY_NATIVE_FROM." || true

# Wine-ICU под системную libicu (для установщиков/.NET при ошибке icuuc68)
if [ "$ONLY_MINGW" -eq 0 ] && [ "$WITH_WINE_ICU" -eq 1 ] && [ -n "$OUT_DIST" ] && [ -d "$OUT_DIST" ]; then
    echo ""
    echo "Сборка и установка wine-icu (системная libicu) в дистрибутив..."
    if [ -d "$DEPS_DIR/wine-icu/.git" ]; then
        echo "Инициализация субмодуля icu в wine-icu..."
        (cd "$DEPS_DIR/wine-icu" && GIT_TERMINAL_PROMPT=0 git submodule update --init --recursive --progress) 2>&1 || true
    fi
    if DEPS_DIR="$DEPS_DIR" "$WINE_ROOT/tools/install-wine-icu.sh" "$OUT_DIST" 2>&1; then
        echo "  wine-icu установлен в lib/wine/icu/."
    else
        echo "  Предупреждение: wine-icu не установлен (нужны: git, cmake, libicu-devel). См. README.md (Troubleshooting: installers and ICU) или ./tools/install-wine-icu.sh" >&2
    fi
fi

# Локальный wine-mono с патчем IconConverter (замена IL-хака source-патчем)
if [ "$ONLY_MINGW" -eq 0 ] && [ "$WITH_WINE_MONO" -eq 1 ] && [ -n "$OUT_DIST" ] && [ -d "$OUT_DIST" ]; then
    echo ""
    echo "Сборка и установка локального wine-mono (patched IconConverter) в дистрибутив..."
    if DEPS_DIR="$DEPS_DIR" WINE_MONO_FORCE_REBUILD="$FORCE_REBUILD_DEPS" "$WINE_ROOT/tools/install-wine-mono.sh" "$OUT_DIST" 2>&1; then
        echo "  wine-mono установлен в share/wine/mono/."
    else
        echo "  Предупреждение: wine-mono не установлен. Проверьте зависимости (wine, make, git, toolchain mono) и лог выше." >&2
    fi
fi
