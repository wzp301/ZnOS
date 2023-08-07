# nasm -o ./mbr/mbr.bin ./mbr/mbr.s
# nasm -o ./mbr/loader.bin ./mbr/loader.s
dd if=./mbr/mbr.bin of=./hd60M.img bs=512 count=1 conv=notrunc
dd if=./mbr/loader.bin of=./hd60M.img bs=512 seek=2 count=3 conv=notrunc
bochs -f bochsrc.disk