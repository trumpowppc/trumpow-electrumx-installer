# electrumx-installer
A script to automate the installation of electrumx 🤖

Installing electrumx isn't really straight-forward (yet). You have to install the latest version of Python and various dependencies for
one of the database engines. Then you have to integrate electrumx into your init system.

`electrumx-installer` simplifies this process to running a single command. All that's left to do for you
is to customise the configuration and to start electrumx.

## Usage
This installs electrumx using the default options:

    wget https://raw.githubusercontent.com/CryptoDevelopmentServices/shic-electrumx-installer/master/bootstrap.sh -O - | bash

You can also set some options if you want more control:

| -d --dbdir | Set database directory (default: /db/) |
|------------|----------------------------------------|
| --update   | Update previously installed version    |
| --leveldb  | Use LevelDB instead of RocksDB         |

For example:

    wget https://raw.githubusercontent.com/CryptoDevelopmentServices/shic-electrumx-installer/master/bootstrap.sh -O - | bash -s - -d /media/ssd/electrum-db


## Operating System Compatibility

The following operating systems are officially supported and automatically being tested against:

| OS              | Status |
|------------------|-------:|
| Ubuntu 20.04     | ![Ubuntu 20.04](https://img.shields.io/github/actions/workflow/status/CryptoDevelopmentServices/shic-electrumx-installer/ubuntu-20.04.yml?branch=main&label=Ubuntu%2020.04) |
| Fedora 29        | ![Fedora 29](https://img.shields.io/github/actions/workflow/status/CryptoDevelopmentServices/shic-electrumx-installer/fedora-29.yml?branch=main&label=Fedora%2029) |
| Debian Stretch   | ![Debian Stretch](https://img.shields.io/github/actions/workflow/status/CryptoDevelopmentServices/shic-electrumx-installer/debian-stretch.yml?branch=main&label=Debian%20Stretch) |
| Debian Buster    | ![Debian Buster](https://img.shields.io/github/actions/workflow/status/CryptoDevelopmentServices/shic-electrumx-installer/debian-buster.yml?branch=main&label=Debian%20Buster) |



If you prefer a different operating system that's not listed here, see
[`distributions/README.md`](https://github.com/CryptoDevelopmentServices/shic-electrumx-installer/blob/master/distributions/README.md) to find out how to add it.
Or open an [issue](https://github.com/CryptoDevelopmentServices/shic-electrumx-installer/issues/new) if you'd rather not do that yourself.
