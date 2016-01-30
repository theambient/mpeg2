
module bitstream;

public import stdint;

import std.exception;

/**
* @brief Bitstream reader and parser
*
* @copyright The code is borrowed from h264bitstream library and translated to D
*/

public class BitstreamReader
{
	public this(const ubyte[] data)
	{
		_data = data;
		start = _data.ptr;
		p = start;
		end = _data.ptr + _data.length;
		bits_left = 8;
	}

	public bool eof() const @property
	{
		return _eof;
	}

	public size_t bits_read() const @property
	{
		return _bits_read;
	}

	public bool is_byte_aligned() const
	{
		return bits_left == 8;
	}

	public void align_to_next_byte()
	{
		if(bits_left != 8)
		{
			p++;
			bits_left = 8;
		}
	}

	public bool read_bool()
	{
		return cast(bool) read_u1;
	}

	public ubyte read_u1()
	{
		ubyte r = 0;

		bits_left--;
		_bits_read += 1;

		if( ! _eof )
		{
			r = ((*(p)) >> bits_left) & 0x01;
		}

		if (bits_left == 0) { p ++; bits_left = 8; }

		return r;
	}

	public void skip_u1()
	{
		bits_left--;
		_bits_read += 1;

		if(bits_left == 0)
		{
			p++;
			bits_left = 8;
		}
	}

	public uint32 peek_u1()
	{
		uint32 r = 0;

		if( ! _eof )
		{
			r = ((*(p)) >> ( bits_left - 1 )) & 0x01;
		}
		return r;
	}


	public uint32 read_u(int n)
	{
		uint32 r = 0;
		int i;
		for (i = 0; i < n; i++)
		{
			r |= ( read_u1() << ( n - i - 1 ) );
		}
		return r;
	}

	public ubyte read_b(int n)
	{
		return cast(ubyte) read_u(n);
	}

	public void skip_u(int n)
	{
		int i;
		for ( i = 0; i < n; i++ )
		{
			skip_u1();
		}
	}

	public uint32 read_f(int n)
	{
		return read_u(n);
	}

	public ubyte read_u8()
	{
		if (bits_left == 8 && ! eof()) // can do fast read
		{
			ubyte r = p[0];
			p++;
			_bits_read += 8;
			return r;
		}

		return cast(ubyte) read_u(8);
	}

	public uint32 read_ue()
	{
		int32 r = 0;
		int i = 0;

		while( (read_u1() == 0) && (i < 32) && (!eof()) )
		{
			i++;
		}
		r = read_u(i);
		r += (1 << i) - 1;
		return r;
	}

	public int32 read_se()
	{
		int32 r = read_ue();
		if (r & 0x01)
		{
			r = (r+1)/2;
		}
		else
		{
			r = -(r/2);
		}
		return r;
	}

	public const(ubyte)[] read_bytes(long len)
	{
		enforce(is_byte_aligned());

		auto actual_len = len;
		if (end - p < actual_len) { actual_len = end - p; }
		if (actual_len < 0) { actual_len = 0; }
		auto buf = p[0..actual_len];
		p += actual_len;
		_bits_read += actual_len * 8;

		return buf;
	}

	public long read_bytes(ubyte[] b)
	{
		auto r = read_bytes(b.length);

		b[0..r.length] = r[0..$];

		return r.length;
	}

	public long skip_bytes(long len)
	{
		enforce(is_byte_aligned());

		auto actual_len = len;
		if (end - p < actual_len) { actual_len = end - p; }
		if (actual_len < 0) { actual_len = 0; }
		if (len < 0) { len = 0; }
		p += actual_len;
		_bits_read += actual_len * 8;

		return actual_len;
	}

	//public uint32 next_bits(int nbits);

	public uint64 next_bytes(int nbytes)
	{
		int i = 0;
		uint64 val = 0;

		if ( (nbytes > 8) || (nbytes < 1) ) { return 0; }
		if (p + nbytes > end) { return 0; }

		for ( i = 0; i < nbytes; i++ ) { val = ( val << 8 ) | p[i]; }
		return val;
	}

	private const ubyte[] _data;
	private const uint8* start;
	private const uint8* end;
	private const(uint8)* p;
	private int bits_left;
	private size_t _bits_read = 0;

	invariant()
	{
		assert(bits_left > 0);
		assert(bits_left <= 8);
		assert(start < end);
		assert(start<=p);
		assert(p<=end);
	}

	private bool _eof() const @property
	{
		return p >= end;
	}
}

unittest
{
	auto bs = new BitstreamReader([0x12, 0x25, 0xf1]);
	auto vals = [0,0,0,1, 0,0,1,0, 0,0,1,0, 0,1,0,1, 1,1,1,1, 0,0,0,1];

	foreach(v; vals)
	{
		assert(bs.read_u1() == v);
	}

	assert(bs.eof);
	assert(bs.bits_read == 24);
}

unittest
{
	auto bs = new BitstreamReader([0x12, 0x25, 0xf1]);
	auto bitstring = [0,0,0,1, 0,0,1,0, 0,0,1,0, 0,1,0,1, 1,1,1,1, 0,0,0,1];
	auto steps = [5,3,9,2,1,4];

	size_t pos = 0;
	foreach(i,s; steps)
	{
		uint32 r = 0;
		auto r_bits = bitstring[pos..pos + s];
		foreach(v; r_bits)
		{
			r <<= 1;
			r |= v;
		}

		assert(r == bs.read_u(s));

		pos += s;
		if(bs.eof)
		{
			break;
		}
	}

	assert(bs.eof);
	assert(pos == bitstring.length);
	assert(bs.bits_read == 24);
}
