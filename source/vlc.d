
module vlc;

import std.array;
import std.typecons;
import bitstream;

private alias VlcTableEntry = Tuple!(uint, uint);
private alias VlcTable = immutable VlcTableEntry[];

private uint read_vlc(uint max_bits)(BitstreamReader bs, VlcTable table)
{
	uint bits = bs.nextbits(max_bits);

	int i = 0;
	while(i < table.length && bits < table[i][0])
	{
		++i;
	}

	bs.skip_u(table[i][1]);

	return i;
}

public ubyte read_mb_inc(BitstreamReader bs)
{
	static VlcTable table = [
		tuple(0b1 << 10,              1),

		tuple(0b011 << 8,             3),
		tuple(0b010 << 8,             3),

		tuple(0b0011 << 7,            4),
		tuple(0b0010 << 7,            4),

		tuple(0b0001_1 << 6,          5),
		tuple(0b0001_0 << 6,          5),

		tuple(0b0000_111 << 4,        7),
		tuple(0b0000_110 << 4,        7),

		tuple(0b0000_1011 << 3,       8),
		tuple(0b0000_1010 << 3,       8),
		tuple(0b0000_1001 << 3,       8),
		tuple(0b0000_1000 << 3,       8),
		tuple(0b0000_0111 << 3,       8),
		tuple(0b0000_0110 << 3,       8),

		tuple(0b0000_0101_11 << 1,   10),
		tuple(0b0000_0101_10 << 1,   10),
		tuple(0b0000_0101_01 << 1,   10),
		tuple(0b0000_0101_00 << 1,   10),
		tuple(0b0000_0100_11 << 1,   10),
		tuple(0b0000_0100_10 << 1,   10),

		tuple(0b0000_0100_011,       11),
		tuple(0b0000_0100_010,       11),
		tuple(0b0000_0100_001,       11),
		tuple(0b0000_0100_000,       11),

		tuple(0b0000_0011_111,       11),
		tuple(0b0000_0011_110,       11),
		tuple(0b0000_0011_101,       11),
		tuple(0b0000_0011_100,       11),
		tuple(0b0000_0011_011,       11),
		tuple(0b0000_0011_010,       11),
		tuple(0b0000_0011_001,       11),
		tuple(0b0000_0011_000,       11),
		tuple(0b0000_0001_000,       11),	// escape
	];

	auto v = bs.read_vlc!11(table);
	assert(v < 34);
	return cast(ubyte)(v+1);
}

// Tables B.2 - B.8
public uint read_mb_type(BitstreamReader bs, ubyte picture_coding_type)
{
	static VlcTable table2 = [
		tuple(0b1 << 1, 1),
		tuple(0b01,     2),
	];

	static VlcTable table3 = [
		tuple(0b1      << 5, 1),
		tuple(0b01     << 4, 2),
		tuple(0b001    << 3, 3),
		tuple(0b00011  << 1, 5),
		tuple(0b00010  << 1, 5),
		tuple(0b00001  << 1, 5),
		tuple(0b000001     , 6),
	];

	static Tuple!(int,int,int)[] table4_first = [

		tuple(0b0000, 0, -1),
		tuple(0b0001, 0, -1),

		tuple(0b0010, 4, 4),
		tuple(0b0011, 4, 5),

		tuple(0b0100, 3, 2),
		tuple(0b0101, 3, 2),

		tuple(0b0110, 3, 3),
		tuple(0b0111, 3, 3),

		tuple(0b1000, 2, 0),
		tuple(0b1001, 2, 0),
		tuple(0b1010, 2, 0),
		tuple(0b1011, 2, 0),

		tuple(0b1100, 2, 1),
		tuple(0b1101, 2, 1),
		tuple(0b1110, 2, 1),
		tuple(0b1111, 2, 1),
	];

	static VlcTable table4_second = [
		tuple(0b00011  << 1, 5),
		tuple(0b00010  << 1, 5),
		tuple(0b000011     , 6),
		tuple(0b000010     , 6),
		tuple(0b000001     , 6),
	];

	uint v = -1;
	uint tmp;
	final switch(picture_coding_type)
	{
		case 1: // I
			v = bs.read_vlc!2(table2);
			break;
		case 2: // P
			v = bs.read_vlc!6(table3);
			break;
		case 3: // B
			tmp = bs.nextbits(4);
			auto t = table4_first[tmp];
			if(t[2] != -1)
			{
				bs.skip_u(t[1]);
				assert(tmp == t[1]);
				v = t[2];
				break;
			}

			v = bs.read_vlc!6(table4_second);
			v += 6;
			break;
	}

	assert(v < 2);

	return v;
}

// Table B.9
public ubyte read_cbp(BitstreamReader bs);


// Table B.10
public byte read_mc(BitstreamReader bs)
{
	static VlcTable table = [
		tuple(0b1            << 10, 1),
		tuple(0b010          << 08, 3),
		tuple(0b0010         << 07, 4),
		tuple(0b00010        << 6,  5),
		tuple(0b0000_110     << 4,  7),
		tuple(0b0000_1010    << 3,  8),
		tuple(0b0000_1000    << 3,  8),
		tuple(0b0000_0110    << 3,  8),

		tuple(0b0000_0101_10 << 1, 10),
		tuple(0b0000_0101_00 << 1, 10),
		tuple(0b0000_0100_10 << 1, 10),

		tuple(0b0000_0100_010    , 11),
		tuple(0b0000_0100_000    , 11),
		tuple(0b0000_0011_110    , 11),
		tuple(0b0000_0011_100    , 11),
		tuple(0b0000_0011_010    , 11),
		tuple(0b0000_0011_000    , 11),
	];

	static assert(table.length == 17);

	byte v = cast(byte) bs.read_vlc!11(table);

	if(v & 0x01)
	{
		v = -v;
	}

	return v;
}

// Table B.11
public byte read_dmvector(BitstreamReader bs)
{
	byte v = bs.read_u1;

	if(v != 0)
	{
		v = bs.read_u!byte(2);

		if(v & 0x1) v = -v;
	}

	return v;
}

public ubyte read_dc_size(BitstreamReader bs, bool luma);
public bool read_dct(BitstreamReader bs, bool first, out short run, out short level);

unittest
{
	auto bs = new BitstreamReader([0b10110100, 0b010_0011_1, 0]);

	assert(bs.read_mb_inc() == 1);
	assert(bs.read_mb_inc() == 2);
	assert(bs.read_mb_inc() == 3);
	assert(bs.read_mb_inc() == 5);
	assert(bs.read_mb_inc() == 4);
	assert(bs.read_mb_inc() == 1);
}

unittest
{
	auto bs = new BitstreamReader([0xff, 0xff, 0xff, 0]);
	assert(bs.read_mb_inc() == 1);
	assert(bs.read_mb_inc() == 1);
	assert(bs.read_mb_inc() == 1);
	assert(bs.read_mb_inc() == 1);
	assert(bs.read_mb_inc() == 1);
	assert(bs.read_mb_inc() == 1);
	assert(bs.read_mb_inc() == 1);
	assert(bs.read_mb_inc() == 1);

}
