# The eReader Project

<p align="center">
  <img src="https://github.com/user-attachments/assets/b5b5db2b-9357-4625-9b8f-fa9a692a3b7a" alt="drawing" style="width:45%;"/>
  <img src="https://github.com/user-attachments/assets/f0c72004-3f0e-4984-8537-b92983d227ca" alt="drawing" style="width:45%;"/>
</p>

eReader is an open source client application for read it later services (currently just Instapaper). eReader is based on KOReader, so it works with Kobo/Kindle/etc. eReader is designed to be simpler to use than KOReader, with the assumption that most users will use it alongside their device's native experience (ie for reading ebooks). eReader also allows you to access to a fully functioning version of KOReader if you so desire.

eReader is currently in active development. Please file an issue for any bugs you run into!

## Installing eReader on Kobo

Currently, the easiest way to install eReader is on top of an existing KOReader install. If you do not already have KOReader, follow [these instructions](https://github.com/koreader/koreader/wiki/Installation-on-Kobo-devices) to install it (using either the semi-automated method or manually installing KFMon and KOReader). If you have installed KOReader previously, make sure you have [the most recent release](https://github.com/koreader/koreader/releases) installed before installing eReader.

Once you have installed it, you can simply check out the eReader code, plug in your Kobo and run this command:
```
./deploy_ereader.sh
```

This will install eReader into your existing install of KOReader, but KOReader will continue to be fully functional. The deploy script also add a shortcut to launch eReader using [NickleMenu](https://github.com/pgaskin/NickelMenu). If you already have a KOReader shortcut menu item, it will continue to work as before. 

## Installing eReader on other devices

Currently eReader has only been tested on Kobo. Installation on other devices should be straightforward if you have a working KOReader install, but you'll have to do it manually as the deploy script above currently only supports Kobo. 

### On Kindle
If you have a jailbroken Kindle and would like to contribute to eReaders's development, please comment on the [issue](https://github.com/quicklywilliam/ereader/issues/7) requesting support!

If you are new to Kindle modding, be advised that jailbreaking a Kindle is fairly involved and there is currently no Jailbreak for the latest firmware version. For more information, visit this [Reddit thread on r/Kindle](https://www.reddit.com/r/kindle/comments/1khoafs/does_anybody_have_any_idea_when_new_jailbreak_for/).

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

[ ] Improved access to device controls (backlight, rotation lock, etc)

[ ] Browsing favorites and archive

[ ] Tagging

[ ] One-click installation

[ ] OTA Updates

## Setting up for development

In order to run eReader in the emulator, you will need to your own OAUTH client keys. You can obtain these credentials by [applying for Instapaper API access](https://www.instapaper.com/api). This isn't needed when running the release builds, at least on Kobo.

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
