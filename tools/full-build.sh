#!/usr/bin/env bash
# Единый пайплайн полной сборки: проверка окружения → MinGW → конфигурация Wine → сборка Wine → DXVK/VKD3D/NVAPI → дистрибутив.
# Запуск из корня дерева Wine: ./tools/full-build.sh [опции]
#
# Опции (те же, что у build-full-wine-deps.sh):
#   --build-mingw-from-source  — собрать MinGW из исходников (30–60 мин)
#   --no-install-wine          — не ставить Wine в дистрибутив
#   --force-rebuild            — всегда пересобирать DXVK / VKD3D-Proton / DXVK-NVAPI
#   --no-bundle-system-libs    — не копировать нативные lib с системы
#   --copy-native-from=DIR     — взять нативные lib из готового дистрибутива
#   --no-wine-icu              — не ставить wine-icu (системная libicu, x86_64 + i386) в дистрибутив
#   --no-wine-mono             — не собирать и не устанавливать локальный wine-mono в дистрибутив
#
# See README.md for details.

set -e

WINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS_DIR="$WINE_ROOT/build-deps"
PASSTHROUGH=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --build-mingw-from-source|--no-install-wine|--no-bundle-system-libs|--force-rebuild|--no-wine-icu|--no-wine-mono) PASSTHROUGH+=("$1") ;;
        --copy-native-from=*) PASSTHROUGH+=("$1") ;;
        --copy-native-from) [ -n "${2:-}" ] && PASSTHROUGH+=("$1" "$2") && shift || { echo "Требуется аргумент для --copy-native-from" >&2; exit 1; }; shift ;;
        *) echo "Неизвестный аргумент: $1" >&2; exit 1 ;;
    esac
    shift
done

echo "========== Полная сборка (Wine + DXVK + VKD3D + DXVK-NVAPI + дистрибутив) =========="
echo ""

# --- Шаг 1: Проверка окружения ---
echo "[1/6] Проверка окружения..."

REQUIRED="meson ninja gcc g++ make flex bison pkg-config"
MISSING=""
for cmd in $REQUIRED; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING="$MISSING $cmd"
    fi
done
if [ -n "$MISSING" ]; then
    echo "Ошибка: не найдены обязательные команды:$MISSING" >&2
    echo "  Установите пакеты (gcc, gcc-c++, make, flex, bison, meson, ninja-build, pkg-config)." >&2
    echo "  See README.md for recommended packages." >&2
    exit 1
fi

for cmd in glslangValidator glslang; do
    if command -v "$cmd" &>/dev/null; then break; fi
    if [ "$cmd" = "glslang" ]; then
        echo "Предупреждение: не найден glslang/glslangValidator. DXVK/VKD3D требуют его для сборки." >&2
    fi
done
if ! pkg-config --exists vulkan 2>/dev/null && [ ! -f /usr/include/vulkan/vulkan.h ] 2>/dev/null; then
    echo "Предупреждение: Vulkan (vulkan-headers) не найден. Установите vulkan-headers для DXVK/VKD3D." >&2
fi

if [ ! -f "$WINE_ROOT/configure" ] || [ ! -d "$WINE_ROOT/tools" ]; then
    echo "Ошибка: запускайте скрипт из корня дерева Wine (где есть configure и tools/)." >&2
    exit 1
fi
echo "  Ок."
echo ""

# --- Шаг 2: Подготовка MinGW ---
echo "[2/6] Подготовка MinGW (скачивание/сборка при необходимости)..."

if [ -f "$DEPS_DIR/.mingw-path" ]; then
    # Используем ранее сохранённый PATH, если компиляторы на месте
    . "$DEPS_DIR/.mingw-path"
fi
if ! command -v x86_64-w64-mingw32-gcc &>/dev/null; then
    # Запускаем deps в режиме только MinGW; он скачает/соберёт и запишет PATH
    "$WINE_ROOT/tools/build-full-wine-deps.sh" --only-mingw "${PASSTHROUGH[@]}" || true
    if [ -f "$DEPS_DIR/.mingw-path" ]; then
        . "$DEPS_DIR/.mingw-path"
    fi
fi
if ! command -v x86_64-w64-mingw32-gcc &>/dev/null; then
    echo "Ошибка: MinGW не найден после подготовки. Запустите:" >&2
    echo "  ./tools/build-full-wine-deps.sh --no-install-wine" >&2
    echo "  или с --build-mingw-from-source для сборки из исходников." >&2
    exit 1
fi
echo "  MinGW: $(command -v x86_64-w64-mingw32-gcc)"
echo ""

# --- Шаг 3: Конфигурация Wine ---
echo "[3/6] Конфигурация Wine..."

NEED_CONFIGURE=0
COMPILER_CHANGED=0
if [ ! -f "$WINE_ROOT/Makefile" ]; then
    NEED_CONFIGURE=1
elif grep -q 'i386_CC = clang' "$WINE_ROOT/Makefile" 2>/dev/null; then
    echo "  Makefile настроен на clang; переконфигурируем с MinGW."
    NEED_CONFIGURE=1
    COMPILER_CHANGED=1
elif grep -q 'x86_64_CC = clang' "$WINE_ROOT/Makefile" 2>/dev/null; then
    echo "  Makefile использует clang для x86_64; переконфигурируем с MinGW."
    NEED_CONFIGURE=1
    COMPILER_CHANGED=1
elif command -v i686-w64-mingw32-gcc &>/dev/null && ! grep -Eq '^PE_ARCHS = .*i386' "$WINE_ROOT/Makefile" 2>/dev/null; then
    echo "  Makefile настроен без WoW64 PE-архитектуры; переконфигурируем с i386 + x86_64."
    NEED_CONFIGURE=1
fi
if [ "$NEED_CONFIGURE" -eq 1 ]; then
    if [ "$COMPILER_CHANGED" -eq 1 ]; then
        echo "  Смена PE-компилятора: очистка stale объектных файлов (libs, dlls)..."
        find "$WINE_ROOT/libs" -path "*/x86_64-windows/*.o" -delete 2>/dev/null
        find "$WINE_ROOT/libs" -path "*/x86_64-windows/*.a" -delete 2>/dev/null
        find "$WINE_ROOT/libs" -path "*/i386-windows/*.o" -delete 2>/dev/null
        find "$WINE_ROOT/libs" -path "*/i386-windows/*.a" -delete 2>/dev/null
    fi
    (cd "$WINE_ROOT" && ./tools/configure-wine-full.sh) || { echo "Ошибка конфигурации Wine." >&2; exit 1; }
else
    echo "  Makefile уже есть и использует MinGW — пропуск."
fi
echo ""

# --- Шаг 4: Сборка Wine ---
echo "[4/6] Сборка Wine (make -j\$(nproc))..."

if [ ! -x "$WINE_ROOT/loader/wine" ] || [ ! -x "$WINE_ROOT/server/wineserver" ]; then
    (cd "$WINE_ROOT" && make -j"$(nproc)") || { echo "Ошибка сборки Wine." >&2; exit 1; }
else
    (cd "$WINE_ROOT" && make -j"$(nproc)") || { echo "Ошибка сборки Wine." >&2; exit 1; }
fi
if [ ! -x "$WINE_ROOT/loader/wine" ] || [ ! -x "$WINE_ROOT/server/wineserver" ]; then
    echo "Ошибка: Wine не собран (нет loader/wine или server/wineserver)." >&2
    exit 1
fi
echo "  Wine собран."
echo ""

# --- Шаг 5 и 6: DXVK/VKD3D/NVAPI + дистрибутив ---
echo "[5/6] Сборка DXVK, VKD3D-Proton, DXVK-NVAPI и формирование дистрибутива..."
echo "[6/6] Установка Wine в dist и копирование нативных lib (если включено)..."
echo ""

"$WINE_ROOT/tools/build-full-wine-deps.sh" "${PASSTHROUGH[@]}"

# Strip "Wine builtin DLL" marker from DXVK/VKD3D/NVAPI DLLs so Wine loads
# them as native (not builtin) when DLL overrides are set to native.
# Glob all WINE-BLEEDING-* dist dirs so rebuilds on different dates are covered.
for gpu_dir in dxvk vkd3d-proton nvapi; do
    for arch in x86_64-windows i386-windows; do
        for dpath in "$WINE_ROOT/dist/WINE-BLEEDING-"*/lib/wine/"$gpu_dir"/"$arch"; do
            [ -d "$dpath" ] || continue
            for dll in "$dpath"/*.dll; do
                [ -f "$dll" ] || continue
                python3 -c "
with open('$dll', 'r+b') as f:
    f.seek(0x40)
    if f.read(16) == b'Wine builtin DLL':
        f.seek(0x40)
        f.write(b'\x00' * 16)
" 2>/dev/null || true
            done
        done
    done
done
echo "  DXVK/VKD3D/NVAPI: stripped Wine builtin markers for native loading"

echo ""
echo "========== Готово =========="
DIST_NAME="${DIST_NAME:-WINE-BLEEDING-$(date +%d%m%Y)}"
echo "Дистрибутив: $WINE_ROOT/dist/$DIST_NAME"
echo "Запуск: $WINE_ROOT/dist/$DIST_NAME/bin/wine --version"

# wine-bleeding runtime layer: write .wb_dist_meta into produced dist (M2)
if [ -x "${WINE_ROOT}/runtime/src/wb-lib/wb-dist.sh" ]; then
  (
    # shellcheck source=../runtime/src/wb-lib/wb-log.sh
    source "${WINE_ROOT}/runtime/src/wb-lib/wb-log.sh"
    # shellcheck source=../runtime/src/wb-lib/wb-json.sh
    source "${WINE_ROOT}/runtime/src/wb-lib/wb-json.sh"
    # shellcheck source=../runtime/src/wb-lib/wb-dist.sh
    source "${WINE_ROOT}/runtime/src/wb-lib/wb-dist.sh"
    DIST_DIR="${WINE_ROOT}/dist/${DIST_NAME}"
    if [ -d "${DIST_DIR}" ]; then
      if ! wb_dist_meta_write "${DIST_DIR}"; then
        echo "wb-dist: manifest write failed for ${DIST_DIR}" >&2
        exit 1
      fi
    fi
  ) || exit 1
fi
