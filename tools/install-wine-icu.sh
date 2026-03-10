#!/usr/bin/env bash
# Сборка wine-icu под системную libicu и установка ICU-DLL в дистрибутив Wine.
# Решает ошибку: find_forwarded_export module not found / function not found для icuuc68.
# Собирает несколько версий ICU из субмодуля (например 68 и 72), все DLL (icuuc68, icuuc72 и т.д.)
# попадают в один каталог дистрибутива — встроенный в Wine icu.dll находит icuuc68.
# Запуск из корня дерева Wine: ./tools/install-wine-icu.sh [путь к дистрибутиву]
# Переменная WINE_ICU_VERSIONS — список версий через пробел, по умолчанию "68.2 72.1".
# Требует: git, cmake, zip, unzip, компилятор (gcc/clang), системные libicu и libicu-devel,
#          MinGW для x86_64 и i686 (x86_64-w64-mingw32-gcc, i686-w64-mingw32-gcc).

set -e

WINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for cmd in zip unzip; do
    command -v "$cmd" &>/dev/null || { echo "Ошибка: не найдена команда $cmd. Установите пакет (apt: zip unzip, dnf: zip unzip)." >&2; exit 1; }
done
DEPS_DIR="${DEPS_DIR:-$WINE_ROOT/build-deps}"
ICU_BUILD_DIR="$DEPS_DIR/wine-icu-build"
ICU_SRC_DIR="$DEPS_DIR/wine-icu"
ZIP_STASH="$DEPS_DIR/wine-icu-zips"

# Путь к дистрибутиву: аргумент или последний WINE-BLEEDING-* в dist/
if [ -n "$1" ]; then
    DIST_DIR="$(cd "$1" && pwd)"
else
    DIST_DIR=""
    for d in "$WINE_ROOT/dist"/WINE-BLEEDING-*; do
        [ -d "$d" ] && DIST_DIR="$d" && break
    done
    [ -z "$DIST_DIR" ] && { echo "Не найден dist (WINE-BLEEDING-*). Укажите путь: $0 /path/to/dist" >&2; exit 1; }
fi

echo "Дистрибутив: $DIST_DIR"
echo "Сборка wine-icu под системную libicu..."

mkdir -p "$DEPS_DIR"
if [ ! -d "$ICU_SRC_DIR" ]; then
    echo "Клонирование wine-icu (полная история нужна для субмодуля icu)..."
    git clone https://gitlab.winehq.org/wine/wine-icu.git "$ICU_SRC_DIR"
fi
cd "$ICU_SRC_DIR"
git pull --depth 1 2>/dev/null || true
# При shallow-клоне (--depth 1) git не знает ревизию субмодуля — подтягиваем историю
if [ -f .git/shallow ]; then
    echo "Подтягивание истории wine-icu для доступа к субмодулю icu..."
    git fetch --unshallow 2>/dev/null || git fetch --depth 500 2>/dev/null || true
fi
echo "Инициализация субмодуля icu (исходники icu4c, репозиторий большой — подождите)..."
GIT_TERMINAL_PROMPT=0 git -c core.askPass= submodule update --init --recursive --progress 2>&1 || { echo "Ошибка: не удалось загрузить субмодуль icu. Проверьте сеть и git." >&2; exit 1; }

# Сборка ZIP: make_package ожидает *-gcc-win32 / *-g++-win32; 32-bit может быть в отдельной директории (mingw32-cross)
MINGW_BIN=""
MINGW32_BIN=""
[ -f "$DEPS_DIR/.mingw-path" ] && . "$DEPS_DIR/.mingw-path" 2>/dev/null || true
for d in "$DEPS_DIR/mingw64-cross/bin" "$DEPS_DIR/x86_64-w64-mingw32-cross/bin" /usr/bin; do
    [ -x "$d/x86_64-w64-mingw32-gcc" ] && MINGW_BIN="$d" && break
done
for d in "$DEPS_DIR/mingw64-cross/bin" "$DEPS_DIR/mingw32-cross/bin" "$DEPS_DIR/i686-w64-mingw32-cross/bin" "$DEPS_DIR/x86_64-w64-mingw32-cross/bin" /usr/bin; do
    [ -x "$d/i686-w64-mingw32-gcc" ] && MINGW32_BIN="$d" && break
done
[ -z "$MINGW32_BIN" ] && MINGW32_BIN="$MINGW_BIN"
if [ -n "$MINGW_BIN" ]; then
    need_wrapper=0
    [ ! -x "$MINGW_BIN/x86_64-w64-mingw32-gcc-win32" ] && need_wrapper=1
    [ ! -x "$MINGW_BIN/x86_64-w64-mingw32-cpp-win32" ] && [ -x "$MINGW_BIN/x86_64-w64-mingw32-cpp" ] && need_wrapper=1
    [ ! -x "$MINGW32_BIN/i686-w64-mingw32-gcc-win32" ] && [ -x "$MINGW32_BIN/i686-w64-mingw32-gcc" ] && need_wrapper=1
    [ ! -x "$MINGW32_BIN/i686-w64-mingw32-cpp-win32" ] && [ -x "$MINGW32_BIN/i686-w64-mingw32-cpp" ] && need_wrapper=1
    if [ "$need_wrapper" -eq 1 ]; then
        ICU_WRAPPER="$DEPS_DIR/wine-icu-mingw-wrapper"
        mkdir -p "$ICU_WRAPPER"
        for arch in x86_64-w64-mingw32 i686-w64-mingw32; do
            for s in gcc g++ cpp; do
                win32="$arch-$s-win32"
                orig="$arch-$s"
                case "$arch" in i686*) dir="$MINGW32_BIN" ;; *) dir="$MINGW_BIN" ;; esac
                [ -n "$dir" ] && [ -x "$dir/$orig" ] && ln -sf "$dir/$orig" "$ICU_WRAPPER/$win32" 2>/dev/null || true
            done
        done
        export PATH="$ICU_WRAPPER:$MINGW_BIN:$MINGW32_BIN:$PATH"
        echo "Используется MinGW: x86_64=$MINGW_BIN, i686=$MINGW32_BIN (обёртки *-win32 для ICU)."
    else
        export PATH="$MINGW_BIN:$MINGW32_BIN:$PATH"
    fi
fi

# Встроенный в Wine icu.dll перенаправляет на icuuc68.u_charsToUChars_68 (экспорт с суффиксом _68).
# make_package по умолчанию собирает ICU с --disable-renaming (экспорты без суффикса). Включаем
# переименование для MinGW-сборки, чтобы icuuc68.dll экспортировал u_charsToUChars_68 и т.д.
if grep -q 'runConfigureICU MinGW.*--disable-renaming' "$ICU_SRC_DIR/make_package" 2>/dev/null; then
    sed -i '/runConfigureICU MinGW/s/ --disable-renaming / /' "$ICU_SRC_DIR/make_package"
    echo "Патч make_package: включено переименование символов (экспорты _68/_72) для совместимости с Wine icu.dll."
    # Удаляем закэшированные ZIP — они собраны без суффиксов, нужна пересборка.
    for f in "$ZIP_STASH"/wine-icu-*.zip; do
        [ -f "$f" ] && rm -f "$f" && echo "  Удалён кэш (пересборка с новыми экспортами): $(basename "$f")"
    done
fi

# Обрезка пробелов и переводов строк.
trim() { echo "$1" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

# Поиск ZIP в wine-icu/build и корне репозитория (make_package кладёт в build/).
find_zip() {
    local pattern="$1"
    for dir in "$ICU_SRC_DIR/build" "$ICU_SRC_DIR"; do
        [ ! -d "$dir" ] && continue
        for f in "$dir"/$pattern; do
            [ -f "$f" ] && echo -n "$f" && return 0
        done
    done
    return 0
}

# Список версий ICU для сборки (из субмодуля icu: release-68-2, release-72-1 и т.д.).
# Все DLL (icuuc68, icuuc72, icudt68, icudt72, ...) попадают в один каталог дистрибутива.
WINE_ICU_VERSIONS="${WINE_ICU_VERSIONS:-68.2 72.1}"
mkdir -p "$ZIP_STASH"
rm -rf "$ICU_BUILD_DIR"
mkdir -p "$ICU_BUILD_DIR"

WINE_ICU64="$DIST_DIR/lib/wine/icu/x86_64-windows"
WINE_ICU32="$DIST_DIR/lib/wine/icu/i386-windows"
mkdir -p "$WINE_ICU64" "$WINE_ICU32"

copy_dlls() {
    local src="$1" arch="$2"
    [ ! -d "$src" ] && return 0
    find "$src" -maxdepth 3 -name "*.dll" -type f -exec cp -f {} "$arch/" \;
}

# Версия в формате 68.2 -> тег репозитория icu release-68-2
version_to_tag() { echo "release-${1//./-}"; }

echo "Версии ICU для сборки: $WINE_ICU_VERSIONS"

for ver in $WINE_ICU_VERSIONS; do
    tag=$(version_to_tag "$ver")
    want_major=$(echo "$ver" | cut -d. -f1)
    echo "---------- ICU $ver (тег $tag) ----------"
    # Переключаем субмодуль icu на нужный тег; git reset --hard чтобы рабочее дерево совпало (в субмодуле .git часто файл, не каталог — проверяем -e)
    if [ -e "$ICU_SRC_DIR/icu/.git" ] && [ -d "$ICU_SRC_DIR/icu/icu4c" ]; then
        pushd "$ICU_SRC_DIR/icu" >/dev/null
        git fetch origin "tag/$tag" 2>/dev/null || true
        git checkout "$tag" 2>/dev/null || { git fetch origin 2>/dev/null; git checkout "$tag" 2>/dev/null; } || \
        { popd >/dev/null; echo "Ошибка: не удалось переключить субмодуль icu на $tag. Проверьте наличие тега (release-68-2, release-72-1 и т.д.)." >&2; exit 1; }
        git reset --hard HEAD
        popd >/dev/null
        # Проверка: исходники должны соответствовать версии (make_package копирует icu/icu4c в build)
        have_major=""
        [ -f "$ICU_SRC_DIR/icu/icu4c/source/common/unicode/uvernum.h" ] && have_major=$(sed -n 's/^#define U_ICU_VERSION_SUFFIX _\([0-9]*\)/\1/p' "$ICU_SRC_DIR/icu/icu4c/source/common/unicode/uvernum.h" | head -1)
        if [ -n "$have_major" ] && [ "$have_major" != "$want_major" ]; then
            echo "Ошибка: после checkout $tag в icu исходники версии $have_major, ожидалась $ver. Удалите кэш и перезапустите: rm -f $ZIP_STASH/wine-icu-*.zip" >&2
            exit 1
        fi
    fi
    echo "$ver" > "$ICU_SRC_DIR/VERSION"

    # Ищем архивы этой версии (make_package создаёт wine-icu-<VERSION>-x86_64.zip и -x86.zip).
    # Если в архиве не те DLL (например для 68.2 попали icuuc72.dll) — удаляем кэш и пересоберём.
    ZIP64=""; ZIP32=""
    for z in "$ZIP_STASH/wine-icu-$ver-x86_64.zip" "$ZIP_STASH/wine-icu-$ver-x86.zip"; do
        [ ! -f "$z" ] && continue
        wrong=$(unzip -l "$z" 2>/dev/null | grep -E "icuuc[0-9]+\.dll" | head -1 | sed 's/.*icuuc\([0-9]*\)\.dll.*/\1/')
        if [ -n "$wrong" ] && [ "$wrong" != "$want_major" ]; then
            rm -f "$z" && echo "  Удалён неверный кэш $(basename "$z") (содержал icuuc$wrong.dll, нужен icuuc$want_major.dll)."
        fi
    done
    [ -f "$ZIP_STASH/wine-icu-$ver-x86_64.zip" ] && ZIP64="$ZIP_STASH/wine-icu-$ver-x86_64.zip"
    [ -f "$ZIP_STASH/wine-icu-$ver-x86.zip" ] && ZIP32="$ZIP_STASH/wine-icu-$ver-x86.zip"
    if [ -z "$ZIP64" ]; then
        for f in "$ICU_SRC_DIR/build"/wine-icu-"$ver"-x86_64.zip "$ICU_SRC_DIR"/wine-icu-"$ver"-x86_64.zip; do
            [ -f "$f" ] && cp -f "$f" "$ZIP_STASH/" && ZIP64="$ZIP_STASH/wine-icu-$ver-x86_64.zip" && break
        done
    fi
    [ -z "$ZIP64" ] && ZIP64=$(find_zip "*$ver*x86_64*.zip") && ZIP64=$(trim "$ZIP64")
    [ -n "$ZIP64" ] && [ -f "$ZIP64" ] && [ "${ZIP64#$ZIP_STASH}" = "$ZIP64" ] && cp -f "$ZIP64" "$ZIP_STASH/wine-icu-$ver-x86_64.zip" && ZIP64="$ZIP_STASH/wine-icu-$ver-x86_64.zip"
    if [ -z "$ZIP32" ]; then
        for f in "$ICU_SRC_DIR/build"/wine-icu-"$ver"-x86.zip "$ICU_SRC_DIR"/wine-icu-"$ver"-x86.zip; do
            [ -f "$f" ] && cp -f "$f" "$ZIP_STASH/" && ZIP32="$ZIP_STASH/wine-icu-$ver-x86.zip" && break
        done
    fi
    [ -z "$ZIP32" ] && ZIP32=$(find_zip "*$ver*x86.zip") && ZIP32=$(trim "$ZIP32")
    [ -n "$ZIP32" ] && [ -f "$ZIP32" ] && [ "${ZIP32#$ZIP_STASH}" = "$ZIP32" ] && cp -f "$ZIP32" "$ZIP_STASH/wine-icu-$ver-x86.zip" && ZIP32="$ZIP_STASH/wine-icu-$ver-x86.zip"

    # Сборка x86_64, если архива нет. make_package копирует $(pwd)/icu/icu4c — нужен ровно ICU_SRC_DIR.
    if [ -z "$ZIP64" ] || [ ! -f "$ZIP64" ]; then
        echo "Сборка wine-icu $ver (x86_64)..."
        cd "$ICU_SRC_DIR"
        ./make_package --x86_64 --zip 2>&1 | tee "$ICU_BUILD_DIR/build64-$ver.log" || { echo "Сборка wine-icu $ver x86_64 не удалась. См. $ICU_BUILD_DIR/build64-$ver.log" >&2; exit 1; }
        for f in "$ICU_SRC_DIR/build"/wine-icu-"$ver"-x86_64*.zip; do
            [ -f "$f" ] && cp -f "$f" "$ZIP_STASH/" && ZIP64="$ZIP_STASH/$(basename "$f")" && break
        done
    fi
    if [ -z "$ZIP64" ] || [ ! -f "$ZIP64" ]; then
        echo "ZIP x86_64 для версии $ver не найден после сборки." >&2
        exit 1
    fi

    # Сборка x86, если архива нет
    if [ -z "$ZIP32" ] || [ ! -f "$ZIP32" ]; then
        echo "Сборка wine-icu $ver (x86)..."
        cd "$ICU_SRC_DIR"
        if ./make_package --x86 --zip 2>&1 | tee "$ICU_BUILD_DIR/build32-$ver.log"; then
            for f in "$ICU_SRC_DIR/build"/wine-icu-"$ver"-x86.zip; do
                [ -f "$f" ] && cp -f "$f" "$ZIP_STASH/" && ZIP32="$ZIP_STASH/$(basename "$f")" && break
            done
        fi
    fi

    # Распаковка и копирование DLL этой версии в общие каталоги дистрибутива
    rm -rf "$ICU_BUILD_DIR"/* 2>/dev/null || true
    ( cd "$ICU_BUILD_DIR" && unzip -o -q "$ZIP64" )
    [ -n "$ZIP32" ] && [ -f "$ZIP32" ] && ( cd "$ICU_BUILD_DIR" && unzip -o -q "$ZIP32" ) 2>/dev/null || true
    for sub in "$ICU_BUILD_DIR"/wine-icu-*-x86_64 "$ICU_BUILD_DIR"/x86_64 "$ICU_BUILD_DIR"/x64; do
        [ -d "$sub" ] && copy_dlls "$sub" "$WINE_ICU64"
    done
    for sub in "$ICU_BUILD_DIR"/wine-icu-*-x86 "$ICU_BUILD_DIR"/x86 "$ICU_BUILD_DIR"/i386 "$ICU_BUILD_DIR"/x32; do
        [ -d "$sub" ] && copy_dlls "$sub" "$WINE_ICU32"
    done
    echo "  ICU $ver: DLL добавлены в дистрибутив."
done

count64=$(find "$WINE_ICU64" -maxdepth 1 -name "*.dll" 2>/dev/null | wc -l)
count32=$(find "$WINE_ICU32" -maxdepth 1 -name "*.dll" 2>/dev/null | wc -l)
echo "Скопировано DLL: x86_64-windows: $count64, i386-windows: $count32"

if [ "$count64" -eq 0 ]; then
    echo "ОШИБКА: в x86_64-windows не скопировано ни одной DLL. Проверьте структуру архива в $ICU_BUILD_DIR." >&2
    ls -la "$ICU_BUILD_DIR" 2>/dev/null || true
    exit 1
fi

echo ""
echo "========== Установка wine-icu завершена успешно =========="
echo "  Версии: $WINE_ICU_VERSIONS (все DLL: icuuc68, icuuc72 и т.д. в одном каталоге)"
echo "  x86_64: $count64 DLL в $WINE_ICU64"
echo "  i386:   $count32 DLL в $WINE_ICU32"
echo ""
echo "Чтобы установщики (BarTender и др.) не падали с «find_forwarded_export icuuc68»:"
echo "скопируйте ICU-DLL из дистрибутива в префикс (и перезапустите установщик):"
echo ""
echo "  cp -f $WINE_ICU64/*.dll \$HOME/PortProton/data/prefixes/DEFAULT/drive_c/windows/system32/"
echo "  cp -f $WINE_ICU32/*.dll \$HOME/PortProton/data/prefixes/DEFAULT/drive_c/windows/syswow64/"
echo ""
echo "Версии задаются через WINE_ICU_VERSIONS (по умолчанию: 68.2 72.1)."
exit 0
