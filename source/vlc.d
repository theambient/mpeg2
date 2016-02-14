
module vlc;

import std.array;
import std.typecons;
import bitstream;

private alias VlcTableEntry = Tuple!(uint, uint);
private alias VlcTable = immutable VlcTableEntry[];
private struct VlcTab
{
	int val;
	int skip;
}

struct DCTtab
{
	byte run, level, len;
}

const int ERROR = -1;

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
public ubyte read_cbp(BitstreamReader bs)
{
	static VlcTable table = [
		tuple(0b111            << 6, 3),

		tuple(0b1101           << 5, 4),
		tuple(0b1100           << 5, 4),
		tuple(0b1011           << 5, 4),
		tuple(0b1010           << 5, 4),

		tuple(0b10011          << 4, 5),
		tuple(0b10010          << 4, 5),
		tuple(0b10001          << 4, 5),
		tuple(0b10000          << 4, 5),
		tuple(0b01111          << 4, 5),
		tuple(0b01110          << 4, 5),
		tuple(0b01101          << 4, 5),
		tuple(0b01100          << 4, 5),
		tuple(0b01011          << 4, 5),
		tuple(0b01010          << 4, 5),
		tuple(0b01001          << 4, 5),
		tuple(0b01000          << 4, 5),

		tuple(0b001111         << 3, 6),
		tuple(0b001110         << 3, 6),
		tuple(0b001101         << 3, 6),
		tuple(0b001100         << 3, 6),

		tuple(0b0010_111       << 2, 7),
		tuple(0b0010_110       << 2, 7),
		tuple(0b0010_101       << 2, 7),
		tuple(0b0010_100       << 2, 7),
		tuple(0b0010_011       << 2, 7),
		tuple(0b0010_010       << 2, 7),
		tuple(0b0010_001       << 2, 7),
		tuple(0b0010_000       << 2, 7),

		tuple(0b0001_1111      << 1, 8),
		tuple(0b0001_1110      << 1, 8),
		tuple(0b0001_1101      << 1, 8),
		tuple(0b0001_1100      << 1, 8),
		tuple(0b0001_1011      << 1, 8),
		tuple(0b0001_1010      << 1, 8),
		tuple(0b0001_1001      << 1, 8),
		tuple(0b0001_1000      << 1, 8),
		tuple(0b0001_0111      << 1, 8),
		tuple(0b0001_0110      << 1, 8),
		tuple(0b0001_0101      << 1, 8),
		tuple(0b0001_0100      << 1, 8),
		tuple(0b0001_0011      << 1, 8),
		tuple(0b0001_0010      << 1, 8),
		tuple(0b0001_0001      << 1, 8),
		tuple(0b0001_0000      << 1, 8),
		tuple(0b0000_1111      << 1, 8),
		tuple(0b0000_1110      << 1, 8),
		tuple(0b0000_1101      << 1, 8),
		tuple(0b0000_1100      << 1, 8),
		tuple(0b0000_1011      << 1, 8),
		tuple(0b0000_1010      << 1, 8),
		tuple(0b0000_1001      << 1, 8),
		tuple(0b0000_1000      << 1, 8),
		tuple(0b0000_0111      << 1, 8),
		tuple(0b0000_0110      << 1, 8),
		tuple(0b0000_0101      << 1, 8),
		tuple(0b0000_0100      << 1, 8),

		tuple(0b0000_0011_1        , 9),
		tuple(0b0000_0011_0        , 9),
		tuple(0b0000_0010_1        , 9),
		tuple(0b0000_0010_0        , 9),
		tuple(0b0000_0001_1        , 9),
		tuple(0b0000_0001_0        , 9),
		tuple(0b0000_0000_1        , 9),
	];

	static immutable ubyte[] cbp = [
		60,  4,  8, 16, 32, 12, 48, 20, 40, 28,
		44, 52, 56,  1, 61,  2, 62, 24, 36,  3,
		63,  5,  9, 17, 33,  6, 10, 18, 34,  7,
		11, 19, 35, 13, 49, 21, 41, 14, 50, 22,
		42, 16, 51, 23, 43, 25, 37, 26, 38, 29,
		45, 53, 57, 30, 46, 54, 58, 31, 47, 55,
		59, 27, 39,  0
	];

	static assert(cbp.length == table.length);

	auto idx = bs.read_vlc!9(table);
	return cbp[idx];
}

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

/* Table B-12, dct_dc_size_luminance, codes 00xxx ... 11110 */
static VlcTab[32] DClumtab0 =
[
	{1, 2}, {1, 2}, {1, 2}, {1, 2}, {1, 2}, {1, 2}, {1, 2}, {1, 2},
	{2, 2}, {2, 2}, {2, 2}, {2, 2}, {2, 2}, {2, 2}, {2, 2}, {2, 2},
	{0, 3}, {0, 3}, {0, 3}, {0, 3}, {3, 3}, {3, 3}, {3, 3}, {3, 3},
	{4, 3}, {4, 3}, {4, 3}, {4, 3}, {5, 4}, {5, 4}, {6, 5}, {ERROR, 0}
];

/* Table B-12, dct_dc_size_luminance, codes 111110xxx ... 111111111 */
static VlcTab[16] DClumtab1 =
[
	{7, 6}, {7, 6}, {7, 6}, {7, 6}, {7, 6}, {7, 6}, {7, 6}, {7, 6},
	{8, 7}, {8, 7}, {8, 7}, {8, 7}, {9, 8}, {9, 8}, {10,9}, {11,9}
];

/* Table B-13, dct_dc_size_chrominance, codes 00xxx ... 11110 */
static VlcTab[32] DCchromtab0 =
[
	{0, 2}, {0, 2}, {0, 2}, {0, 2}, {0, 2}, {0, 2}, {0, 2}, {0, 2},
	{1, 2}, {1, 2}, {1, 2}, {1, 2}, {1, 2}, {1, 2}, {1, 2}, {1, 2},
	{2, 2}, {2, 2}, {2, 2}, {2, 2}, {2, 2}, {2, 2}, {2, 2}, {2, 2},
	{3, 3}, {3, 3}, {3, 3}, {3, 3}, {4, 4}, {4, 4}, {5, 5}, {ERROR, 0}
];

/* Table B-13, dct_dc_size_chrominance, codes 111110xxxx ... 1111111111 */
static VlcTab[32] DCchromtab1 =
[
	{6, 6}, {6, 6}, {6, 6}, {6, 6}, {6, 6}, {6, 6}, {6, 6}, {6, 6},
	{6, 6}, {6, 6}, {6, 6}, {6, 6}, {6, 6}, {6, 6}, {6, 6}, {6, 6},
	{7, 7}, {7, 7}, {7, 7}, {7, 7}, {7, 7}, {7, 7}, {7, 7}, {7, 7},
	{8, 8}, {8, 8}, {8, 8}, {8, 8}, {9, 9}, {9, 9}, {10,10}, {11,10}
];

public ubyte read_dc_size_luma(BitstreamReader bs)
{
	auto bits = bs.nextbits(5);
	VlcTab e;
	if (bits<31)
	{
		e = DClumtab0[bits];
	}
	else
	{
		bits = bs.nextbits(9) - 0x1f0;
		e = DClumtab1[bits];
	}

	bs.skip_u(e.skip);
	return cast(ubyte) e.val;
}

public ubyte read_dc_size_chroma(BitstreamReader bs)
{
	auto bits = bs.nextbits(5);
	VlcTab e;
	if (bits<31)
	{
		e = DClumtab0[bits];
	}
	else
	{
		bits = bs.nextbits(10) - 0x3e0;
		e = DClumtab1[bits];
	}

	bs.skip_u(e.skip);
	return cast(ubyte) e.val;
}

public ubyte read_dc_size(BitstreamReader bs, bool luma)
{
	if(luma)
		return bs.read_dc_size_luma();
	else
		return bs.read_dc_size_chroma();
}

/* Table B-14, DCT coefficients table zero,
 * codes 0100 ... 1xxx (used for first (DC) coefficient)
 */
DCTtab[12] DCTtabfirst =
[
	{0,2,4}, {2,1,4}, {1,1,3}, {1,1,3},
	{0,1,1}, {0,1,1}, {0,1,1}, {0,1,1},
	{0,1,1}, {0,1,1}, {0,1,1}, {0,1,1}
];

/* Table B-14, DCT coefficients table zero,
 * codes 0100 ... 1xxx (used for all other coefficients)
 */
DCTtab[12] DCTtabnext =
[
	{0,2,4},  {2,1,4},  {1,1,3},  {1,1,3},
	{64,0,2}, {64,0,2}, {64,0,2}, {64,0,2}, /* EOB */
	{0,1,2},  {0,1,2},  {0,1,2},  {0,1,2}
];

/* Table B-14, DCT coefficients table zero,
 * codes 000001xx ... 00111xxx
 */
DCTtab[60] DCTtab0 =
[
	{65,0,6}, {65,0,6}, {65,0,6}, {65,0,6}, /* Escape */
	{2,2,7}, {2,2,7}, {9,1,7}, {9,1,7},
	{0,4,7}, {0,4,7}, {8,1,7}, {8,1,7},
	{7,1,6}, {7,1,6}, {7,1,6}, {7,1,6},
	{6,1,6}, {6,1,6}, {6,1,6}, {6,1,6},
	{1,2,6}, {1,2,6}, {1,2,6}, {1,2,6},
	{5,1,6}, {5,1,6}, {5,1,6}, {5,1,6},
	{13,1,8}, {0,6,8}, {12,1,8}, {11,1,8},
	{3,2,8}, {1,3,8}, {0,5,8}, {10,1,8},
	{0,3,5}, {0,3,5}, {0,3,5}, {0,3,5},
	{0,3,5}, {0,3,5}, {0,3,5}, {0,3,5},
	{4,1,5}, {4,1,5}, {4,1,5}, {4,1,5},
	{4,1,5}, {4,1,5}, {4,1,5}, {4,1,5},
	{3,1,5}, {3,1,5}, {3,1,5}, {3,1,5},
	{3,1,5}, {3,1,5}, {3,1,5}, {3,1,5}
];

/* Table B-15, DCT coefficients table one,
 * codes 000001xx ... 11111111
*/
DCTtab[252] DCTtab0a =
[
	{65,0,6}, {65,0,6}, {65,0,6}, {65,0,6}, /* Escape */
	{7,1,7}, {7,1,7}, {8,1,7}, {8,1,7},
	{6,1,7}, {6,1,7}, {2,2,7}, {2,2,7},
	{0,7,6}, {0,7,6}, {0,7,6}, {0,7,6},
	{0,6,6}, {0,6,6}, {0,6,6}, {0,6,6},
	{4,1,6}, {4,1,6}, {4,1,6}, {4,1,6},
	{5,1,6}, {5,1,6}, {5,1,6}, {5,1,6},
	{1,5,8}, {11,1,8}, {0,11,8}, {0,10,8},
	{13,1,8}, {12,1,8}, {3,2,8}, {1,4,8},
	{2,1,5}, {2,1,5}, {2,1,5}, {2,1,5},
	{2,1,5}, {2,1,5}, {2,1,5}, {2,1,5},
	{1,2,5}, {1,2,5}, {1,2,5}, {1,2,5},
	{1,2,5}, {1,2,5}, {1,2,5}, {1,2,5},
	{3,1,5}, {3,1,5}, {3,1,5}, {3,1,5},
	{3,1,5}, {3,1,5}, {3,1,5}, {3,1,5},
	{1,1,3}, {1,1,3}, {1,1,3}, {1,1,3},
	{1,1,3}, {1,1,3}, {1,1,3}, {1,1,3},
	{1,1,3}, {1,1,3}, {1,1,3}, {1,1,3},
	{1,1,3}, {1,1,3}, {1,1,3}, {1,1,3},
	{1,1,3}, {1,1,3}, {1,1,3}, {1,1,3},
	{1,1,3}, {1,1,3}, {1,1,3}, {1,1,3},
	{1,1,3}, {1,1,3}, {1,1,3}, {1,1,3},
	{1,1,3}, {1,1,3}, {1,1,3}, {1,1,3},
	{64,0,4}, {64,0,4}, {64,0,4}, {64,0,4}, /* EOB */
	{64,0,4}, {64,0,4}, {64,0,4}, {64,0,4},
	{64,0,4}, {64,0,4}, {64,0,4}, {64,0,4},
	{64,0,4}, {64,0,4}, {64,0,4}, {64,0,4},
	{0,3,4}, {0,3,4}, {0,3,4}, {0,3,4},
	{0,3,4}, {0,3,4}, {0,3,4}, {0,3,4},
	{0,3,4}, {0,3,4}, {0,3,4}, {0,3,4},
	{0,3,4}, {0,3,4}, {0,3,4}, {0,3,4},
	{0,1,2}, {0,1,2}, {0,1,2}, {0,1,2},
	{0,1,2}, {0,1,2}, {0,1,2}, {0,1,2},
	{0,1,2}, {0,1,2}, {0,1,2}, {0,1,2},
	{0,1,2}, {0,1,2}, {0,1,2}, {0,1,2},
	{0,1,2}, {0,1,2}, {0,1,2}, {0,1,2},
	{0,1,2}, {0,1,2}, {0,1,2}, {0,1,2},
	{0,1,2}, {0,1,2}, {0,1,2}, {0,1,2},
	{0,1,2}, {0,1,2}, {0,1,2}, {0,1,2},
	{0,1,2}, {0,1,2}, {0,1,2}, {0,1,2},
	{0,1,2}, {0,1,2}, {0,1,2}, {0,1,2},
	{0,1,2}, {0,1,2}, {0,1,2}, {0,1,2},
	{0,1,2}, {0,1,2}, {0,1,2}, {0,1,2},
	{0,1,2}, {0,1,2}, {0,1,2}, {0,1,2},
	{0,1,2}, {0,1,2}, {0,1,2}, {0,1,2},
	{0,1,2}, {0,1,2}, {0,1,2}, {0,1,2},
	{0,1,2}, {0,1,2}, {0,1,2}, {0,1,2},
	{0,2,3}, {0,2,3}, {0,2,3}, {0,2,3},
	{0,2,3}, {0,2,3}, {0,2,3}, {0,2,3},
	{0,2,3}, {0,2,3}, {0,2,3}, {0,2,3},
	{0,2,3}, {0,2,3}, {0,2,3}, {0,2,3},
	{0,2,3}, {0,2,3}, {0,2,3}, {0,2,3},
	{0,2,3}, {0,2,3}, {0,2,3}, {0,2,3},
	{0,2,3}, {0,2,3}, {0,2,3}, {0,2,3},
	{0,2,3}, {0,2,3}, {0,2,3}, {0,2,3},
	{0,4,5}, {0,4,5}, {0,4,5}, {0,4,5},
	{0,4,5}, {0,4,5}, {0,4,5}, {0,4,5},
	{0,5,5}, {0,5,5}, {0,5,5}, {0,5,5},
	{0,5,5}, {0,5,5}, {0,5,5}, {0,5,5},
	{9,1,7}, {9,1,7}, {1,3,7}, {1,3,7},
	{10,1,7}, {10,1,7}, {0,8,7}, {0,8,7},
	{0,9,7}, {0,9,7}, {0,12,8}, {0,13,8},
	{2,3,8}, {4,2,8}, {0,14,8}, {0,15,8}
];

/* Table B-14, DCT coefficients table zero,
 * codes 0000001000 ... 0000001111
 */
DCTtab[8] DCTtab1 =
[
	{16,1,10}, {5,2,10}, {0,7,10}, {2,3,10},
	{1,4,10}, {15,1,10}, {14,1,10}, {4,2,10}
];

/* Table B-15, DCT coefficients table one,
 * codes 000000100x ... 000000111x
 */
DCTtab[8] DCTtab1a =
[
	{5,2,9}, {5,2,9}, {14,1,9}, {14,1,9},
	{2,4,10}, {16,1,10}, {15,1,9}, {15,1,9}
];

/* Table B-14/15, DCT coefficients table zero / one,
 * codes 000000010000 ... 000000011111
 */
DCTtab[16] DCTtab2 =
[
	{0,11,12}, {8,2,12}, {4,3,12}, {0,10,12},
	{2,4,12}, {7,2,12}, {21,1,12}, {20,1,12},
	{0,9,12}, {19,1,12}, {18,1,12}, {1,5,12},
	{3,3,12}, {0,8,12}, {6,2,12}, {17,1,12}
];

/* Table B-14/15, DCT coefficients table zero / one,
 * codes 0000000010000 ... 0000000011111
 */
DCTtab[16] DCTtab3 =
[
	{10,2,13}, {9,2,13}, {5,3,13}, {3,4,13},
	{2,5,13}, {1,7,13}, {1,6,13}, {0,15,13},
	{0,14,13}, {0,13,13}, {0,12,13}, {26,1,13},
	{25,1,13}, {24,1,13}, {23,1,13}, {22,1,13}
];

/* Table B-14/15, DCT coefficients table zero / one,
 * codes 00000000010000 ... 00000000011111
 */
DCTtab[16] DCTtab4 =
[
	{0,31,14}, {0,30,14}, {0,29,14}, {0,28,14},
	{0,27,14}, {0,26,14}, {0,25,14}, {0,24,14},
	{0,23,14}, {0,22,14}, {0,21,14}, {0,20,14},
	{0,19,14}, {0,18,14}, {0,17,14}, {0,16,14}
];

/* Table B-14/15, DCT coefficients table zero / one,
 * codes 000000000010000 ... 000000000011111
 */
DCTtab[16] DCTtab5 =
[
	{0,40,15}, {0,39,15}, {0,38,15}, {0,37,15},
	{0,36,15}, {0,35,15}, {0,34,15}, {0,33,15},
	{0,32,15}, {1,14,15}, {1,13,15}, {1,12,15},
	{1,11,15}, {1,10,15}, {1,9,15}, {1,8,15}
];

/* Table B-14/15, DCT coefficients table zero / one,
 * codes 0000000000010000 ... 0000000000011111
 */
DCTtab[16] DCTtab6 =
[
	{1,18,16}, {1,17,16}, {1,16,16}, {1,15,16},
	{6,3,16}, {16,2,16}, {15,2,16}, {14,2,16},
	{13,2,16}, {12,2,16}, {11,2,16}, {31,1,16},
	{30,1,16}, {29,1,16}, {28,1,16}, {27,1,16}
];

public bool read_dct(BitstreamReader bs, bool first, out short run, out short level)
{
	auto code = bs.nextbits(16);
	DCTtab tab;

	if (code>=16384)
		tab = DCTtabnext[(code>>12)-4];
	else if (code>=1024)
		tab = DCTtab0[(code>>8)-4];
	else if (code>=512)
		tab = DCTtab1[(code>>6)-8];
	else if (code>=256)
		tab = DCTtab2[(code>>4)-16];
	else if (code>=128)
		tab = DCTtab3[(code>>3)-16];
	else if (code>=64)
		tab = DCTtab4[(code>>2)-16];
	else if (code>=32)
		tab = DCTtab5[(code>>1)-16];
	else if (code>=16)
		tab = DCTtab6[code-16];
	else
	{
		throw new Exception("invalid Huffman code");
	}

	bs.skip_u(tab.len);

    if (tab.run == 64) /* end_of_block */
		return false;

	if (tab.run==65) /* escape */
	{
		tab.run = cast(ubyte) bs.read_u(6);

		tab.level = cast(ubyte) bs.read_u(8);

		if (tab.level == 0)
			tab.level = cast(ubyte) bs.read_u(8);
		else if (tab.level == 128)
			tab.level = cast(ubyte)(bs.read_u(8) - 256);
		else if (tab.level > 128)
			tab.level -= 256;

		if(tab.level < 0)
			tab.level = -tab.level;
	}

	run = tab.run;
	level = tab.level;
	return true;
}

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

unittest
{
	auto bs = new BitstreamReader([0b11101111, 0x00100110, 0x00000111, 1,1]);
	// 60, 28, 6, 31
	assert(bs.read_cbp() == 60);
	assert(bs.read_cbp() == 28);
	assert(bs.read_cbp() == 06);
	assert(bs.read_cbp() == 31);
}
