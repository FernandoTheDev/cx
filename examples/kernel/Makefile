all: os.img

boot.bin: boot.asm
	nasm -f bin boot.asm -o boot.bin

entry.o: entry.asm
	nasm -f elf32 entry.asm -o entry.o

kernel.o:
	cx --cflags="-m32 -ffreestanding -fno-pie -fno-pic -fno-stack-protector -c" kernel.cx -o kernel.o --gcc --no-header

kernel.bin: entry.o kernel.o
	ld -m elf_i386 -T linker.ld entry.o kernel.o -o kernel.bin

os.img: boot.bin kernel.bin
	cat boot.bin kernel.bin > os.img
	truncate -s 1440K os.img

run: os.img
	qemu-system-x86_64 -drive format=raw,file=os.img,index=0,media=disk

clean:
	rm -f *.bin *.o os.img
