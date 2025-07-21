# The eReader Project

<p align="center">
  <img src="https://github.com/user-attachments/assets/4baac2a7-6a21-41b1-b0c3-4ccf395bb932" alt="drawing" style="width:45%;"/>
  <img src="https://github.com/user-attachments/assets/0c857390-adaa-4afc-a35a-f0bffa95c781" alt="drawing" style="width:45%;"/>
  
</p>

eReader is an open source client application for read it later services (currently just Instapaper). eReader is based on KOReader, so it works with Kobo/Kindle/etc. eReader is designed to be simpler to use than KOReader, with the assumption that most users will use it alongside their device's native experience (ie for reading ebooks). eReader also allows you to access to a fully functioning version of KOReader if you so desire.

eReader is currently in active development. Please file an issue for any bugs you run into!

## Installing eReader on Kobo and Kindle

Currently, the easiest way to install eReader is on top of an existing KOReader install. If you have installed KOReader previously, make sure you have [the most recent release](https://github.com/koreader/koreader/releases) installed before installing eReader. If you do not have KOReader installed, see below.

Once you KOReader is installed, simply check out the eReader repo, plug in your device and run this command:
```
./deploy_ereader.sh
```

This will install eReader into your existing install of KOReader, but KOReader will continue to be fully functional. The deploy script also add a shortcut to launch eReader using [NickleMenu](https://github.com/pgaskin/NickelMenu) on Kobo or [KUAL](https://www.mobileread.com/forums/showthread.php?t=203326) on Kindle.

### Installing KOReader on Kobo
Follow [these instructions](https://github.com/koreader/koreader/wiki/Installation-on-Kobo-devices) to install KOReader on Kobo (using either the semi-automated method or manually installing KFMon and KOReader).

### On Kindle
To install KOReader on Kindle, you need a jailbroken Kindle. Follow [this guide](https://kindlemodding.org/jailbreaking/) to jailbreak your Kindle. Once you have jailbroken your Kindle, follow [these instructions](https://github.com/koreader/koreader/wiki/Installation-on-Kindle-devices) to install KOReader.

### On Pocketbook/reMarkable/Boox etc

Please file an issue requesting support if you own an e-ink device besides a Kobo or Kindle! It is likely that eReader will work fine once installed, but we need help testing and improving the install process on such devices.

## Features

Currently support is limited to Instapaper. Support for other services, including Readwise Reader, is planned for the future.

[x] Authenticate with Instapaper account

[x] Browse saved articles

[x] Download articles and images for offline reading

[x] Open and read articles

[x] Favorite, Unfavorite and Archive Articles

[x] Save new articles

[x] Offline request queueing (actions like archive, favorite, etc) and graceful offline support

[x] Configurable pre-fetching articles

[x] Highlighting text (beta)

[x] Access to device controls (backlight, rotation lock, etc)

[] Improved text styling controls

[ ] Browsing favorites and archive

[ ] Tagging

[ ] One-click installation

[ ] OTA Updates

## Setting up for development

In order to run eReader in the emulator, you will need to your own OAUTH client keys. You can obtain these credentials by [applying for Instapaper API access](https://www.instapaper.com/api). This isn't needed when running the release builds.

Once you have them, create a `secrets.txt` file in ~/.config/koreader with your Instapaper API credentials:

```
instapaper_ouath_consumer_key = "your_consumer_key"
instapaper_oauth_consumer_secret = "your_consumer_secret"
```

After this, follow the [typical steps](https://github.com/koreader/koreader/blob/master/doc/Building.md) for building and running koreader.

## Contributing

This plugin is under active development. Get in touch if you'd like to contribute!

## License

GPL-3.0-or-later
