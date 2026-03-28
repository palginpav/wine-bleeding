#!/usr/bin/env bash
# Конфигурация Wine с максимальным набором фич (для полной самодостаточной сборки).
# Запуск из корня дерева Wine: ./tools/configure-wine-full.sh
# Обычно вызывается из full-build.sh после подготовки MinGW (build-deps).
# MinGW ищется: 1) в PATH (в т.ч. после .mingw-path), 2) в build-deps (как в build-full-wine-deps.sh).
# Рекомендуемые пакеты для полной сборки см. в README.md.

set -e

WINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS_DIR="$WINE_ROOT/build-deps"
cd "$WINE_ROOT"

# Подключить PATH с MinGW, если уже готов (full-build.sh или предыдущий запуск deps)
if [ -f "$DEPS_DIR/.mingw-path" ]; then
    . "$DEPS_DIR/.mingw-path"
fi
# Если MinGW ещё не в PATH — искать в типичных каталогах build-deps (как в build-full-wine-deps.sh)
if ! command -v x86_64-w64-mingw32-gcc &>/dev/null && ! command -v mingw64-gcc &>/dev/null; then
    for dir in "$DEPS_DIR/mingw64-cross/bin" "$DEPS_DIR/x86_64-w64-mingw32-cross/bin"; do
        if [ -x "$dir/x86_64-w64-mingw32-gcc" ]; then
            export PATH="$dir:$PATH"
            break
        fi
    done
fi
if ! command -v i686-w64-mingw32-gcc &>/dev/null; then
    for dir in "$DEPS_DIR/mingw64-cross/bin" "$DEPS_DIR/mingw32-cross/bin" "$DEPS_DIR/i686-w64-mingw32-cross/bin"; do
        if [ -x "$dir/i686-w64-mingw32-gcc" ]; then
            export PATH="$dir:$PATH"
            break
        fi
    done
fi

# Проверка MinGW для --enable-archs и --with-mingw=gcc (сборка под MinGW — приоритет)
MINGW_GCC=""
if command -v x86_64-w64-mingw32-gcc &>/dev/null || command -v mingw64-gcc &>/dev/null; then
    if command -v i686-w64-mingw32-gcc &>/dev/null; then
        ENABLE_ARCHS="--enable-archs=i386,x86_64"
        MINGW_GCC="--with-mingw=gcc"
    else
        echo "Предупреждение: не найден i686-w64-mingw32-gcc. Для WoW64 будет только x86_64." >&2
        ENABLE_ARCHS=""
        MINGW_GCC="--with-mingw=gcc"
    fi
else
    echo "Ошибка: MinGW не найден. Запустите сначала:" >&2
    echo "  ./tools/build-full-wine-deps.sh --only-mingw" >&2
    echo "  или полный пайплайн: ./tools/full-build.sh" >&2
    exit 1
fi

# Очистка stale объектных файлов при смене PE-компилятора (clang↔gcc):
# clang использует MSVC name mangling для C++, gcc — Itanium.
# Если не очистить, линковка c++/c++abi/icu падает с undefined references.
if [ -f "$WINE_ROOT/Makefile" ]; then
    OLD_CC=$(grep '^x86_64_CC = ' "$WINE_ROOT/Makefile" 2>/dev/null | sed 's/x86_64_CC = //')
    if [ -n "$OLD_CC" ]; then
        NEW_CC="x86_64-w64-mingw32-gcc"
        command -v "$NEW_CC" &>/dev/null || NEW_CC="clang"
        case "$OLD_CC" in
            *clang*) OLD_ABI=msvc ;;
            *)       OLD_ABI=itanium ;;
        esac
        case "$NEW_CC" in
            *clang*) NEW_ABI=msvc ;;
            *)       NEW_ABI=itanium ;;
        esac
        if [ "$OLD_ABI" != "$NEW_ABI" ]; then
            echo "Смена PE-компилятора ($OLD_CC → $NEW_CC): очистка stale C++ объектов..."
            find "$WINE_ROOT/libs" -path "*-windows/*.o" -delete 2>/dev/null
            find "$WINE_ROOT/libs" -path "*-windows/*.a" -delete 2>/dev/null
        fi
    fi
fi

# Максимум фич: не отключаем ничего (--without-* не передаём).
# --with-x — явно запрашиваем X.
# --enable-build-id — полезно для отладки.
if [ -n "$ENABLE_ARCHS" ]; then
    echo "Конфигурация Wine (WoW64: i386 + x86_64) со всеми доступными фичами..."
    ./configure \
        $ENABLE_ARCHS \
        $MINGW_GCC \
        --with-x \
        --enable-build-id \
        "$@"
else
    echo "Конфигурация Wine (x86_64) со всеми доступными фичами..."
    ./configure \
        --enable-win64 \
        $MINGW_GCC \
        --with-x \
        --enable-build-id \
        "$@"
fi

echo ""
echo "Конфигурация завершена. Запустите: make -j\$(nproc)"
echo "Полный пайплайн (Wine + DXVK + дистрибутив): ./tools/full-build.sh"
