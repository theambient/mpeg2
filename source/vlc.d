
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

public uint read_mb_type(BitstreamReader bs, ubyte picture_coding_type)
{
	static VlcTable table = [
		tuple(1 << 1, 1),
		tuple(01,     2),
	];

	auto v = bs.read_vlc!2(table);
	assert(v < 2);

	return v;
}

public ubyte read_mc(BitstreamReader bs);
public ubyte read_mr(BitstreamReader bs);
public ubyte read_dmvector(BitstreamReader bs);
public ubyte read_cbp(BitstreamReader bs);
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
