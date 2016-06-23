
module decoder;

import std.array;
import std.exception;
import std.math;
import std.stdio;
import std.string;
import stdint;
import bitstream;
import vlc;
import macroblock;
import matrix;
import dct;
import fast_dct;
import math;

const MACROBLOCK_SIZE = 16;
const ZERO_MV = (short[2]).init;

class Plane
{
	private short[] _pixels;
	private size_t _width;
	private size_t _height;

	this(size_t width, size_t height)
	{
		_width = width;
		_height = height;
		_pixels = new short[width * height];
	}

	ref short opIndex(size_t x, size_t y)
	{
		return _pixels[y * _width + x];
	}

	short opIndex(size_t x, size_t y) const
	{
		return _pixels[y * _width + x];
	}
}

class Picture
{
	Plane[3] planes; // YUV

	uint dts;
	uint pts;
	size_t width;
	size_t height;

	this(size_t width, size_t height)
	{
		this.width = width;
		this.height = height;

		foreach(i; 0..3)
		{
			planes[i] = new Plane(width, height);
		}
	}

	uint width_in_mb() @property const
	{
		return cast(uint) width / MACROBLOCK_SIZE;
	}

	uint height_in_mb() @property const
	{
		return cast(uint) height / MACROBLOCK_SIZE;
	}

	void dump_block(const short[64] block, int mba, ulong comp, string comment = "")
	{
		writefln("MBA #%d block #%d%s: ", mba, comp, comment);

		for(size_t i=0; i<8; ++i)
		{
			writef("    ");
			for(size_t j=0; j<8; ++j)
			{
				writef("%3d ", block[i*8+j]);
			}
			writeln();
		}
		writeln();
	}
}

class PictureBuilder
{
	int previous_macroblock_address = -1;
	PictureHeader ph;
	short[3] dct_pred;
	short[2][2][2] PMV;
	Picture pic;
	Picture[] dpb;

	this(PictureHeader ph, Picture[] dpb)
	{
		this.ph = ph;
		this.dpb = dpb;
		this.pic = new Picture(ph.si.width, ph.si.height);
	}

	void process(const ref MacroBlock mb)
	{
		if(mb.incr > 1)
		{
			process_skipped_mbs(mb.incr - 1);
		}

		int mba = previous_macroblock_address + mb.incr;
		previous_macroblock_address = mba;
		//mb.dump2(mba, true);
		//mb.dump();

		motion_compensate(mb);

		if(ph.picture_coding_type == PictureType.I
			&& (!mb.p.intra || mb.incr > 1))
		{
			reset_dc_predictors();
		}
		uint bx = (mba % pic.width_in_mb) * MACROBLOCK_SIZE;
		uint by = (mba / pic.width_in_mb) * MACROBLOCK_SIZE;

		foreach(uint bi; 0..mb.block_count)
		{
			uint cc = (bi < 4)? 0 : ((bi & 1) + 1);

			short[64] block;

			//dump_block(b.coeffs, mba, bi);

			block = reorder_coefs(mb.blocks[bi].coeffs, ph.alternate_scan);

			block[0] += dct_pred[cc];
			dct_pred[cc] = block[0];

			iquant(block, bi, mb);
			//dump_block(block, mba, bi, " (dct)");
			fast_idct_annexA(block);
			//dump_block(block, mba, bi, " (rec samples)");

			add_block(block, cc, bi, bx, by);
		}

	}

	private void process_skipped_mbs(int num)
	{
		if(ph.picture_coding_type == PictureType.P)
		{
			reset_mv_predictors();
			for(int s = previous_macroblock_address + 1; s<previous_macroblock_address + num + 1; ++s)
			{
				apply_mv(s, ZERO_MV);
			}
		}
	}

	private void motion_compensate(const ref MacroBlock mb)
	{
		enforce(mb.predinfo.type == PredictionType.Frame);
		enforce(mb.predinfo.mv_format == MvFormat.Frame);
		enforce(mb.predinfo.dmv == false);

		if(ph.picture_coding_type == PictureType.P && mb.p.motion_forward == false)
		{
			apply_mv(previous_macroblock_address, ZERO_MV);
			reset_mv_predictors();
			return;
		}

		foreach(r; 0..mb.predinfo.motion_vector_count)
		{
			if(mb.p.motion_forward)
			{
				motion_compensate(mb, r, 0);
			}
			if(mb.p.motion_backward)
			{
				motion_compensate(mb, r, 1);
			}
		}
	}

	void motion_compensate(const ref MacroBlock mb, int r, int s)
	{
		foreach(t; 0..2)
		{
			auto r_size = ph.f_code[s][t] - 1;
			auto f = (1 << r_size);
			auto high = 16 * f - 1;
			auto low = -16 * f;
			auto range = 32 * f;

			short delta;
			if(f == 1 || mb.motion_code[r][s][t] == 0)
			{
				delta = mb.motion_code[r][s][t];
			}
			else
			{
				delta = cast(short)(((abs(mb.motion_code[r][s][t]) - 1) * f) + mb.motion_residual[r][s][t] + 1);
				if (mb.motion_code[r][s][t] < 0)
					delta = -delta;
			}

			short prediction = PMV[r][s][t];

			auto v = cast(short)(prediction + delta);
			if(v < low) v += range;
			if(v > high) v -= range;

			PMV[r][s][t] = v;
		}

		// form block prediction

		int mba = previous_macroblock_address;

		apply_mv(mba, PMV[r][s]);
	}

	private void apply_mv(int mba, const ref short[2] mv)
	{
		enforce(dpb.length > 0);
		auto rf = dpb.back;

		uint bx = (mba % pic.width_in_mb) * MACROBLOCK_SIZE;
		uint by = (mba / pic.width_in_mb) * MACROBLOCK_SIZE;
		//writefln("mv[%s][%s][%d][%d]: %d %d", bx, by, r, s, mvx1, mvy1);

		/*
		short scalex, scaley;

		final switch(ph.si.chroma_format)
		{
			case  ChromaFormat.C444:
				scaley = 1;
				scaley = 1;
				break;
			case ChromaFormat.C422:
				scalex = 1;
				scaley = 2;
				break;
			case ChromaFormat.C420:
				scalex = 2;
				scaley = 2;
				break;
		}

		mvx1 /= scalex;
		mvx2 /= scalex;
		mvy1 /= scaley;
		mvy2 /= scaley;
		*/

		short[2] mv1 = mv[] / 2;
		short[2] mv2 = mv1[] + mv[] % 2;

		foreach(cc; 0..3)
		{
			for(int y=by; y<by + 16; ++y)
			{
				for(int x=bx; x<bx + 16; ++x)
				{
					const auto v = (rf.planes[cc][x + mv1[0], y + mv1[1]] + rf.planes[cc][x + mv2[0], y + mv2[1]]) / 2;
					pic.planes[cc][x, y] += v;
				}
			}
		}
	}

	void add_block(const ref short[64] block, uint cc, uint comp, uint bx, uint by)
	{
		auto plane = pic.planes[cc];
		short base = 0;
		if(ph.picture_coding_type == PictureType.I)
		{
			base = 128;
		}

		if(cc == 0 || ph.si.chroma_format == ChromaFormat.C444)
		{
			int cx = (comp % 2) * 8;
			int cy = (comp / 2) * 8;

			for(int i=0; i<8; ++i)
			{
				for(int j=0; j<8; ++j)
				{
					plane[bx + cx + j, by + cy + i] += cast(short) saturate!(int, 0, 255)(block[i * 8 + j] + base);
				}
			}
		}
		else if(ph.si.chroma_format == ChromaFormat.C420)
		{
			for(int i=0; i<8; ++i)
			{
				for(int j=0; j<8; ++j)
				{
					const auto v = cast(short) saturate!(int, 0, 255)(block[i * 8 + j] + base);

					plane[bx + 2 * j    , by + 2 * i    ] += v;
					plane[bx + 2 * j + 1, by + 2 * i    ] += v;
					plane[bx + 2 * j    , by + 2 * i + 1] += v;
					plane[bx + 2 * j + 1, by + 2 * i + 1] += v;
				}
			}
		}
		else if(ph.si.chroma_format == ChromaFormat.C422)
		{
			int cy = (comp / 2) * 8;

			for(int i=0; i<8; ++i)
			{
				for(int j=0; j<8; ++j)
				{
					const auto v = cast(short) saturate!(int, 0, 255)(block[i * 8 + j] + base);
					plane[bx + 0 + j, by + cy + i] += v;
					plane[bx + 8 + j, by + cy + i] += v;
				}
			}
		}
	}

	private void reset_dc_predictors()
	{
		foreach(i; 0..3)
		{
			//dct_pred[i] = DCT_PRED_DEFAULT[ph.intra_dc_precision];
			dct_pred[i] = 0;
		}
	}

	private void reset_mv_predictors()
	{
		PMV = PMV.init;
	}

	void process_new_slice(Slice s)
	{
		reset_dc_predictors();
		previous_macroblock_address = int(s.slice_vert_pos * pic.width_in_mb) - 1;
	}

	private short[64] reorder_coefs(short[64] c, int scan_id)
	{
		short[64] r;

		for(int i=0; i<64; ++i)
		{
			r[SCAN_MATRIX[scan_id][i]] = c[i];
		}

		return r;
	}

	alias quant_saturate = saturate!(short, -2048, 2047);

	private void iquant(ref short[64] b, ulong c, const ref MacroBlock mb)
	{
		auto quantiser_scale = QUANTISER_SCALE_MATRIX[ph.q_scale_type][mb.s.quantiser_scale_code];
		int cc = ph.si.chroma_format == ChromaFormat.C420? 0: (c >= 4);
		int w = (mb.p.intra? 0: 1) + 2 * cc;

		b[0] *=  INTRA_DC_MULT[ph.intra_dc_precision];
		b[0] = quant_saturate(b[0]);

		short sum = b[0]; // for mismatch control
		for(int i=1; i<64; ++i)
		{
			auto k = mb.p.intra?0:sign(b[i]);
			b[i] = cast(short)((2 * b[i] + k) * DEFAULT_QUANT_MATRIX[w][i] * quantiser_scale / 32);

			b[i] = quant_saturate(b[i]);

			sum |= b[i];
		}

		// mismatch control
		if((sum & 1) == 0)
		{
			b[63] += (b[63]&1)? -1: 1;
		}
	}
}

enum PictureStructure
{
	Reserved    = 0,
	TopField    = 1,
	BottomField = 2,
	Frame       = 3,
}

enum PictureType
{
	I = 1,
	P = 2,
	B = 3,
}

class PictureHeader
{
	SequenceInfo si;

	uint temporal_reference;
	PictureType picture_coding_type;
	uint vbv_delay;

	ubyte[2][2] f_code;
	ubyte intra_dc_precision;
	ubyte picture_structure;
	bool top_field_first;
	bool frame_pred_frame_dct;
	bool concealment_motion_vectors;
	bool q_scale_type;
	bool intra_vlc_format;
	bool alternate_scan;
	bool repeat_first_field;
	bool chroma_420_type;
	bool progressive_frame;
	bool composite_display_flag;

	// if composite_display_flag
	bool v_axis;
	ubyte field_sequence;
	bool sub_carrier;
	ubyte burst_amplitude;
	ubyte sub_carrier_phase;

	this(SequenceInfo si)
	{
		this.si = si;
	}

	void parse(BitstreamReader bs)
	{
		temporal_reference = bs.read_u(10);
		picture_coding_type = cast(PictureType) bs.read_b(3);
		vbv_delay = bs.read_u(16);

		if(picture_coding_type == 2 || picture_coding_type == 3)
		{
			bs.skip_u(4);
		}

		if(picture_coding_type == 3)
		{
			bs.skip_u(4);
		}

		ubyte extra_bit = bs.read_u1;
		while(extra_bit == 1)
		{
			bs.skip_u(8);
		}
	}

	void parse_extension(BitstreamReader bs)
	{
		f_code[0][0] = bs.read_b(4);
		f_code[0][1] = bs.read_b(4);
		f_code[1][0] = bs.read_b(4);
		f_code[1][1] = bs.read_b(4);

		intra_dc_precision = bs.read_b(2);
		picture_structure = bs.read_b(2);

		top_field_first = bs.read_bool();
		frame_pred_frame_dct = bs.read_bool();
		concealment_motion_vectors = bs.read_bool();
		q_scale_type = bs.read_bool();
		intra_vlc_format = bs.read_bool();
		alternate_scan = bs.read_bool();
		repeat_first_field = bs.read_bool();
		chroma_420_type = bs.read_bool();
		progressive_frame = bs.read_bool();
		composite_display_flag = bs.read_bool();

		if(composite_display_flag)
		{
			v_axis = bs.read_bool;
			field_sequence = bs.read_b(3);
			sub_carrier = bs.read_bool;
			burst_amplitude = bs.read_b(7);
			sub_carrier_phase = bs.read_b(8);
		}

		enforce(!concealment_motion_vectors, "concealment_motion_vectors are not implemented");
	}

	void dump()
	{
		string pictype;
		final switch(picture_coding_type)
		{
			case PictureType.I: pictype = "I"; break;
			case PictureType.P: pictype = "P"; break;
			case PictureType.B: pictype = "B"; break;
		}

		string picstruct;
		final switch(picture_structure)
		{
			case 0b01: picstruct = "Top Field"; break;
			case 0b10: picstruct = "Bottom Field"; break;
			case 0b11: picstruct = "Frame"; break;
		}

		writefln("pic #%04d %s %s", temporal_reference, pictype, picstruct);
	}
}

enum Profile
{
	Simple,
	Main,
	SnrScalable,
	SpartialyScalable,
	High,
}

enum Level
{
	Low,
	Main,
	High1440,
	High,
}

enum ChromaFormat
{
	C420 = 1,
	C422 = 2,
	C444 = 3,
}

Profile parse_profile(ubyte profile)
{
	final switch(profile)
	{
		case 0b101:
			return Profile.Simple;
		case 0b100:
			return Profile.Main;
		case 0b011:
			return Profile.SnrScalable;
		case 0b010:
			return Profile.SpartialyScalable;
		case 0b001:
			return Profile.High;
	}
}

Level parse_level(ubyte level)
{
	final switch(level)
	{
		case 0b1010:
			return Level.Low;
		case 0b1000:
			return Level.Main;
		case 0b0110:
			return Level.High1440;
		case 0b0100:
			return Level.High;
	}
}

ChromaFormat parse_chroma_format(ubyte b)
{
	final switch(b)
	{
		case 0x01:
			return ChromaFormat.C420;
		case 0x02:
			return ChromaFormat.C422;
		case 0x03:
			return ChromaFormat.C444;
	}
}

class SequenceInfo
{
	int width;
	int height;
	int aspect_ratio;
	int frame_rate;
	int bitrate;
	int vbv_buffer_size;

	bool load_intra_quantizer_matrix;
	bool load_non_intra_quantizer_matrix;
	ubyte[64] intra_quantizer_matrix;
	ubyte[64] non_intra_quantizer_matrix;

	Profile profile;
	Level level;

	bool progressive;
	bool low_delay;
	ChromaFormat chroma_format;

	void dump()
	{
		writefln("SEQUENCE HEADER:");
		writefln("\tsize: %sx%s", width, height);
		writefln("\tfr: %s", frame_rate);
		writefln("\tar: %s", aspect_ratio);
		writefln("\tbitrate: %s Mbps", bitrate * 400 / 1000000);
		writefln("\tvbv_buffer_size: %s",vbv_buffer_size);

		if(load_intra_quantizer_matrix)
		{
			writefln("\tintra qmatrix:");
			foreach(i; 0..8)
			{
				write("\t\t");
				foreach(j; 0..8)
				{
					write("%02d ", intra_quantizer_matrix[i*8 + j]);
				}
				writeln("");
			}

		}

		if(load_non_intra_quantizer_matrix)
		{
			writefln("\tnon_intra qmatrix:");
			foreach(i; 0..8)
			{
				write("\t\t");
				foreach(j; 0..8)
				{
					write("%02d ", non_intra_quantizer_matrix[i*8 + j]);
				}
				writeln("");
			}

		}

		writefln("profile: %s", profile);
		writefln("level:   %s", level);
		writefln("progressive:   %s", progressive);
		writefln("low_delay:   %s", low_delay);
		writefln("chroma_format:   %s", chroma_format);
	}
}

class Slice
{
	this(PictureHeader ph)
	{
		this.ph = ph;
	}

	void parse(BitstreamReader bs, uint start_code)
	{
		slice_vert_pos = start_code - 1;

		if(ph.si.height > 2800)
		{
			slice_vert_pos = bs.read_u(3) << slice_vert_pos;
		}

		//TODO: implement priority_breakpoint

		quantiser_scale_code = bs.read_u(5);

		if(bs.peek_u1)
		{
			slice_extension_flag = bs.read_bool;
			intra_slice = bs.read_bool;
			slice_picture_id_enable = bs.read_bool;
			slice_picture_id = bs.read_b(6);

			while(bs.peek_u1)
			{
				bs.read_u1;
				bs.skip_u(8);
			}
		}

		bs.skip_u1;
	}

	void dump()
	{
		writefln("slice %02d:", slice_vert_pos);
		writefln("\tquantiser_scale_code:    %d", quantiser_scale_code);
		writefln("\tslice_extension_flag:    %d", slice_extension_flag);
		writefln("\tintra_slice:             %d", intra_slice);
		writefln("\tslice_picture_id_enable: %d", slice_picture_id_enable);
		writefln("\tslice_picture_id:        %d", slice_picture_id);
	}

	PictureHeader ph;
	int slice_vert_pos;
	int quantiser_scale_code;
	bool slice_extension_flag;
	bool intra_slice;
	bool slice_picture_id_enable;
	ubyte slice_picture_id;

}

struct GopInfo
{
	int time_code;
	bool closed_gop;
	bool broken_link;
}

class Decoder
{
	this(string filename)
	{
		_init_parsers();

		auto f = File(filename, "rb");

		auto content = new ubyte[f.size()];

		content = f.rawRead(content);

		this.bs = new BitstreamReader(content);
	}

	Picture decode()
	{
		while(!bs.eof && !_picture_ready())
		{
			_read_syntax_element();
			//_process_syntax_element(se);
		}

		if(_pics.length == 0)
		{
			return null;
		}

		auto f = _pics[0];
		_pics.popFront();
		return f;
	}

	void _read_syntax_element()
	{
		bs.align_to_next_byte();

		int state = 0;
		int cnt = 0;

		immutable int[][] xlat = [
			[1, 0],
			[2, 0],
			[0, 3],
		];

		while(state < 3 && !bs.eof)
		{
			ubyte b = bs.read_u8();
			++cnt;

			if(b != 0 && b != 1)
			{
				state = 0;
				continue;
			}

			state = xlat[state][b];
		}

		if(bs.eof)
		{
			return;
		}

		if(cnt > 3) writefln("warn: skipped %s bytes to next high level syntax element", cnt - 3);

		auto start_code = bs.read_u8();

		//writefln("found syntax element %X (%s) at position %s", start_code, start_code_str(start_code), bs.bits_read() / 8);
		if(start_code !in _parsers)
		{
			writefln("unknown syntax element %X (%s) at position %s", start_code, start_code_str(start_code), bs.bits_read() / 8);
			return;
		}

		_parsers[start_code](start_code);
	}

	private void _maybe_flush_picture()
	{
		if(picture_builder !is null)
		{
			_pics ~= picture_builder.pic;
			dpb ~= picture_builder.pic;
			if(dpb.length > 2)
			{
				dpb = dpb[$-2..$];
			}
			picture_builder = null;
		}
	}

	private void _parse_sequence_header(ubyte start_code)
	{
		_maybe_flush_picture();

		si = new SequenceInfo;

		si.width = bs.read_u(12);
		si.height = bs.read_u(12);
		si.aspect_ratio = bs.read_u(4);

		int frame_rate_code = bs.read_u(4);

		si.bitrate = bs.read_u(18);
		bs.skip_u1();
		si.vbv_buffer_size = bs.read_u(10);
		bs.skip_u1();

		si.load_intra_quantizer_matrix = cast(bool) bs.read_u1;

		if(si.load_intra_quantizer_matrix)
		{
			bs.read_bytes(si.intra_quantizer_matrix);
			throw new Exception("custom quantizer matrixes are not supported");
		}

		si.load_non_intra_quantizer_matrix = cast(bool) bs.read_u1;

		if(si.load_non_intra_quantizer_matrix)
		{
			bs.read_bytes(si.non_intra_quantizer_matrix);
			throw new Exception("custom quantizer matrixes are not supported");
		}

		//si.dump();
	}

	private void _parse_sequence_extention()
	{
		ubyte pal = bs.read_u8(); // profile_and_level

		if(pal & 0x80)
		{
			throw new Exception("escape code not implemented");
		}
		else
		{
			si.profile = parse_profile((pal & 0x70) >> 4);
			si.level = parse_level(pal & 0x0f);
		}

		si.progressive = cast(bool) bs.read_u1;
		si.chroma_format = parse_chroma_format(cast(ubyte) bs.read_u(2));

		si.width = (si.width & 0x0fff) | (bs.read_u(2) << 12);
		si.height = (si.height & 0x0fff) | (bs.read_u(2) << 12);
		si.bitrate = (si.bitrate & 0x03ffff) | (bs.read_u(12) << 18);
		enforce(bs.read_u1 == 1, "marker bit");
		si.vbv_buffer_size = (si.vbv_buffer_size & 0x03ff) | (bs.read_u(8) << 10);

		si.low_delay = cast(bool) bs.read_u1;

		// frame_rate
		bs.read_u(2);
		bs.read_u(5);

		enforce(bs.is_byte_aligned);
		si.dump();
	}

	private void _parse_extension(ubyte start_code)
	{
		ubyte extension_start_code = bs.read_b(4);

		_ext_parsers[extension_start_code]();
	}

	private void _parse_picture_extension()
	{
		ph.parse_extension(bs);
		writefln("================== pic #%03d =======================", ph.temporal_reference);
		ph.dump();
		//expected_extension = ExpectedExtension.ExtensionAndUserData;
		//extension_i = 2;
	}

	private void _parse_slice(ubyte start_code)
	{
		auto s = new Slice(ph);

		s.parse(bs, start_code);
		//s.dump();

		picture_builder.process_new_slice(s);

		do {
			auto mb = MacroBlock(s);
			auto oldp = bs.bits_read;
			mb.parse(bs);
			auto newp = bs.bits_read;
			//writefln("mb: %d -> %d (%d)", oldp, newp, newp - oldp);
			picture_builder.process(mb);
		} while( bs.nextbits(23) != 0);
	}

	private void _parse_picture_header(ubyte start_code)
	{
		_maybe_flush_picture();
		ph = new PictureHeader(si);
		ph.parse(bs);
		picture_builder = new PictureBuilder(ph, dpb);
	}

	private void _parse_extension_and_user_data(int i)
	{
		writefln("extension_and_user_data(%d)", i);
	}

	private void _parse_group_of_picture_header(ubyte start_code)
	{
		gopi.time_code = bs.read_u(25);
		gopi.closed_gop = bs.read_bool;
		gopi.broken_link = bs.read_bool;

		//expected_extension = ExpectedExtension.ExtensionAndUserData;
		//extension_i = 1;
	}

	private bool _picture_ready()
	{
		return _pics.length > 0;
	}

	private void _init_parsers()
	{
		_parsers[0x00] = &_parse_picture_header;
		_parsers[0xb3] = &_parse_sequence_header;
		_parsers[0xb5] = &_parse_extension;
		_parsers[0xb8] = &_parse_group_of_picture_header;

		foreach(ubyte sc; 0x01..0xaf)
		{
			_parsers[sc] = &this._parse_slice;
		}

		_ext_parsers[0x01] = &_parse_sequence_extention;
		_ext_parsers[0x08] = &_parse_picture_extension;
	}

	private alias Parser = void delegate (ubyte);
	private alias ExtParser = void delegate ();

	private BitstreamReader bs;
	private Parser[ubyte] _parsers;
	private ExtParser[ubyte] _ext_parsers;
	private SequenceInfo si;
	private GopInfo gopi;
	private PictureHeader ph;
	private PictureBuilder picture_builder;
	private Picture[] _pics;
	private Picture[] dpb;
}

enum ExpectedExtension
{
	Sequence,
	Picture,
	ExtensionAndUserData,
}

extern string start_code_str(ubyte start_code)
{
	byte	number;
	string str = null;
	switch (start_code)
	{
		// H.262 start codes
		case 0x00: str = "Picture"; break;
		case 0xB0: str = "Reserved"; break;
		case 0xB1: str = "Reserved"; break;
		case 0xB2: str = "User data"; break;
		case 0xB3: str = "SEQUENCE HEADER"; break;
		case 0xB4: str = "Sequence error"; break;
		case 0xB5: str = "Extension start"; break;
		case 0xB6: str = "Reserved"; break;
		case 0xB7: str = "SEQUENCE END"; break;
		case 0xB8: str = "Group start"; break;

		// System start codes - 13818-1 p32 Table 2-18 stream_id
		// If these occur, then we're seeing PES headers
		// - maybe we're looking at transport stream data?
		case 0xBC: str = "SYSTEM START: Program stream map"; break;
		case 0xBD: str = "SYSTEM START: Private stream 1"; break;
		case 0xBE: str = "SYSTEM START: Padding stream"; break;
		case 0xBF: str = "SYSTEM START: Private stream 2"; break;
		case 0xF0: str = "SYSTEM START: ECM stream"; break;
		case 0xF1: str = "SYSTEM START: EMM stream"; break;
		case 0xF2: str = "SYSTEM START: DSMCC stream"; break;
		case 0xF3: str = "SYSTEM START: 13522 stream"; break;
		case 0xF4: str = "SYSTEM START: H.222 A stream"; break;
		case 0xF5: str = "SYSTEM START: H.222 B stream"; break;
		case 0xF6: str = "SYSTEM START: H.222 C stream"; break;
		case 0xF7: str = "SYSTEM START: H.222 D stream"; break;
		case 0xF8: str = "SYSTEM START: H.222 E stream"; break;
		case 0xF9: str = "SYSTEM START: Ancillary stream"; break;
		case 0xFF: str = "SYSTEM START: Program stream directory"; break;

		default: str = null; break;
	}

	if (str != null)
	{

	}
	else if (start_code == 0x47)
		str = "TRANSPORT STREAM sync byte";
	else if (start_code >= 0x01 && start_code <= 0xAF)
		str = format("Slice, vertical posn %d", start_code);
	else if (start_code >= 0xC0 && start_code <=0xDF)
	{
		number = start_code & 0x1F;
		str = format("SYSTEM START: Audio stream %02x",number);
	}
	else if (start_code >= 0xE0 && start_code <= 0xEF)
	{
		number = start_code & 0x0F;
		str = format("SYSTEM START: Video stream %x",number);
	}
	else if (start_code >= 0xFC && start_code <= 0xFE)
		str = "SYSTEM START: Reserved data stream";
	else
		str = "SYSTEM START: Unrecognised stream id";

	return str;
}
