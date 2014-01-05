cryptsetup-nuke-keys
====================

A patch for cryptsetup (1.6.1) which adds the option to nuke all keyslots given a certain passphrase.
<pre>
root@kali:~# cryptsetup luksAddNuke /dev/sda5
Enter any existing passphrase: 		(existing password)
Enter new passphrase for key slot:	(set the nuke password)
</pre>

Once the machine is rebooted and you are prompted for the LVM decryption passphrase. 
If you provide the nuke password, all password keyslots get deleted, rendering the encrypted LVM volume inaccessible.


