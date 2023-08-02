dd if=./mbr/mbr.bin of=./hd60M.img bs=512 count=1 conv=notrunc
bochs -f bochsrc.disk