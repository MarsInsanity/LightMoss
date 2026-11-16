LightMoss for the Retroid Pocket Mini V2
=========================================

LightMoss is a small base system that starts spruce. On the Mini V2 it lives
on the internal storage next to Android: 4 GB taken from the end of
Android's data partition. spruce lives on the card.

This card boots LightMoss once, to install it.

1. OpenABL (once)
   LightMoss is started by OpenABL, an open bootloader for Qualcomm
   handhelds (github.com/OpenHandheldCollective/OpenABL), the one ROCKNIX
   uses. If ROCKNIX's install already put it on the device, skip this.
   Otherwise, in Android, as root: copy the openabl folder of this card to
   Android's internal storage, run backup_abl.sh, then flash_abl.sh. With
   an unlocked bootloader, from a PC instead:
       fastboot flash abl_a openabl/abl_signed-SM8250.elf
       fastboot flash abl_b openabl/abl_signed-SM8250.elf
   restore_abl.sh puts the saved bootloader back.

2. Boot this card
   Hold Volume Down while powering on to open OpenABL's menu. Set
   "Boot mode" to Linux and "Boot source" to Auto, then Start.

3. Install on the internal storage
   ANDROID'S DATA IS ERASED: its partition changes size, so Android
   formats it (apps, settings, its internal storage) on its next start.
   Back up first. Android itself stays and still starts.
   Create an empty file named
       lightmoss-install
   next to this text (on the card's LMBOOT partition, from a PC),
   connect the charger and boot the card. It installs, renames the file
   lightmoss-install.done and restarts into the internal LightMoss.
   (Over SSH: lightmoss-install-internal.)

4. spruce
   Copy spruce onto the card's SPRUCEOS partition (made on the card's
   first boot), or format the whole card for spruce as on any device.

Switching
   OpenABL starts what "Boot mode" says (Linux: LightMoss). Holding
   Volume Up at power-on starts the other one (Android). Its menu
   (Volume Down) has both, and "Uninstall CFW" removes LightMoss from
   the internal storage, giving the space back to Android.

Updates
   The LightMoss Update app in spruce downloads a release and writes it
   to LightMoss's second system copy while the first runs. If the new one
   does not start, the device goes back to the old one by itself.

Files you can create here (on the internal LMBOOT over SSH: /boot):
   lightmoss-debug      logs to logs/ at every start, spruce's text on screen
   headphones-invert    for a headphone jack reported the wrong way round
