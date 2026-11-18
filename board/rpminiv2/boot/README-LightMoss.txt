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
   Android's internal storage, run backup_abl.sh, then flash_abl.sh (it
   checks the copy first and refuses a damaged one). With an unlocked
   bootloader, from a PC instead:
       fastboot flash abl_a openabl/abl_signed-SM8250.elf
       fastboot flash abl_b openabl/abl_signed-SM8250.elf
   restore_abl.sh puts the saved bootloader back: copy abl_a.img and
   abl_b.img to a PC, as step 3 erases Android's internal storage.

2. Boot this card
   Hold Volume Down while powering on to open OpenABL's menu. Set
   "Boot mode" to Linux and "Boot source" to Auto, then Start.

3. Install on the internal storage
   ANDROID'S DATA IS ERASED: its partition gives LightMoss its last 4 GB,
   so Android formats it (apps, settings, its internal storage) on its
   next start and sets itself up like a new device (should its recovery
   ask instead, choose "Factory data reset"). Back up first. Android
   itself stays and still starts.
   Create an empty file named
       lightmoss-install
   next to this text (on the card's LMBOOT partition, from a PC),
   connect the charger and boot the card. It installs, renames the file
   lightmoss-install.done and restarts into the internal LightMoss. If it
   cannot, the file becomes lightmoss-install.failed, lightmoss-install.log
   says why, and the card starts as before. A power cut on the way does no
   harm: the card starts until the install has been finished.
   (Over SSH: lightmoss-install-internal.)

   ROCKNIX (or another system) on the internal storage: name the file
       lightmoss-install-replace
   instead. That system's partitions are removed, with all that is on
   them. Android's data stays when they leave LightMoss enough room.

4. spruce
   Copy spruce onto the card's SPRUCEOS partition (made on the card's
   first boot), or format the whole card for spruce as on any device.

Switching
   OpenABL starts what "Boot mode" says (Linux: LightMoss). Holding
   Volume Up at power-on starts the other one (Android). Its menu
   (Volume Down) has both, and "Uninstall CFW" removes LightMoss from
   the internal storage, giving the space back to Android.

Repair
   With LightMoss on the internal storage, OpenABL starts it rather than
   this card. To start the card: hold Volume Down at power-on, open
   "Boot entries" and pick the LightMoss entry marked "(card)" (or set
   "Boot source" to SD card, and back to Auto afterwards). Creating
   lightmoss-install here then repairs the internal LightMoss: its system
   becomes this card's, keeping its Wi-Fi networks, SSH keys and
   settings; Android is not touched.

Updates
   The LightMoss Update app in spruce downloads a release and writes it
   to LightMoss's second system copy on the internal storage while the
   first runs; your Wi-Fi networks, SSH keys and Bluetooth pairings come
   along. If the new one does not start (or spruce does not come up on
   it), the device restarts and, after three tries, goes back to the old
   one by itself. LightMoss running from this card is not updated over
   the air (the card has room for one copy). Never write a new card image
   over a card whose SPRUCEOS holds your games and saves: it is erased.
   Copy them off first, or use another card.

Files you can create here (on the internal LMBOOT over SSH: /boot):
   lightmoss-debug      logs to logs/ at every start, spruce's text on screen
   headphones-invert    for a headphone jack reported the wrong way round
