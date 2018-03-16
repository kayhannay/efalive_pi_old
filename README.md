# efaLive PI project

This project contains a build script to create a SD card image with efaLive for the RaspberryPi.

## Binaries and documentation

For more information about efaLive, have a look to the efaLive documentation on [my homepage](http://www.hannay.de/index.php/efalive).

## Related projects
* [Debian GNU/Linux project](http://www.debian.-org/)
* [efaLive Docker](https://github.com/efalive/efalive_docker) - the Docker file to create an efaLive development environment
* [efaLive CD](https://github.com/efalive/efalive_cd) - the live CD build configuration
* [efaLive PI](https://github.com/efalive/efalive_pi) - efaLive for the RaspberryPi (this project)
* [efaLive](https://github.com/efalive/efalive) - the glue code between Debian and the efa software
* [efa 2](https://github.com/efalive/efa2) - the Debian package configuration of the efa software
* [efa](http://efa.nmichael.de/) - the rowing and canoeing log book software

## Requirements
You need a Debian system. It might work on other Debian based systems as well, but it is not tested. You need the packages qemu-user-static, parted and debootstrap for sure, other tools are more or less standard on a Debian system.

## How to build
You can create a RaspberryPi image by calling

```shell
sudo ./build.sh
```

in the root directory of the project. The build script will download many files, so it will consume some space on your hard drive and will take some time, be patient.

Once the build has finished, you should have a file called efaLivePi_2.5.img in the project root directory. This can be written to a SD card by using dd

```shell
sudo dd if=efaLivePi_2.5.img of=/dev/mmcblk0 bs=1M
```

Be careful with the parameter for 'of='! YOU WILL OVERWRITE IMPORTANT DATA if you choose the wrong device here!

