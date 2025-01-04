# Dummy Simple Distrobox Manager Documentation

## Basic Overview:

Dummy Simple Distrobox Manager uses two references for every distrobox it creates.

The first is the actual distrobox itself created using distrobox-create and viewable with distrobox-list.

The second is the "Working Directory" that contains all of the user files of that distrobox and is where the distrobox opens by default when entered. This is the directory you specified during initial setup and is listed as "DISTROBOX_DIR" within your settings.cfg

Dummy Simple Distrobox Manager makes this distinction to give the user the ability to have a home directory for each of their distroboxes and so that the files used by the distroboxes to do not pollute the users primary home folder with files that are not relevant to the host.

This is a design choice that I as the developer have made, I may add the ability to not use this functionality later.

## Getting Started:




