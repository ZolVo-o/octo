# Maintainer: OCTO contributors
pkgname=octo-git
pkgver=r1
pkgrel=1
pkgdesc='Arch Linux package manager with a Rust TUI and C++ backend'
arch=('x86_64')
url='https://github.com/ZolVo-o/octo'
license=('MIT')
depends=('curl' 'git' 'pacman')
makedepends=('gcc' 'rust')
provides=('octo')
conflicts=('octo')
source=('git+https://github.com/ZolVo-o/octo.git')
sha256sums=('SKIP')

pkgver() {
    cd "$srcdir/octo"
    printf 'r%s.%s' "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
}

build() {
    cd "$srcdir/octo"
    mkdir -p target
    g++ -std=c++17 -O2 -Wall -Wextra backend/octo_backend.cpp -o target/octo-backend
    cargo build --release --locked --bin octo-tui
}

check() {
    cd "$srcdir/octo"
    cargo test --locked
}

package() {
    cd "$srcdir/octo"
    install -Dm755 octo "$pkgdir/usr/bin/octo"
    install -Dm755 target/octo-backend "$pkgdir/usr/lib/octo/octo-backend"
    install -Dm755 target/release/octo-tui "$pkgdir/usr/lib/octo/octo-tui"
    install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
    install -Dm644 README.md "$pkgdir/usr/share/doc/$pkgname/README.md"
}
