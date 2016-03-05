
module macroblock;

import std.exception;
import std.stdio;
import bitstream;
import vlc;
import decoder;

enum PredictionType
{
	Field,
	Frame,
	DualPrime,
	Mc16x8,
}

enum MvFormat
{
	Field,
	Frame,
}

struct Block
{
	short[64] coeffs;
}

struct MacroBlock
{
	Slice s;
	MbParams p;
	ubyte incr;
	uint type;
	ubyte spartial_temporal_weight_code;
	ubyte motion_type;
	ubyte dct_type;
	ubyte quantiser_scale_code;
	bool[2][2] motion_vertical_field_select;
	byte[2][2][2] motion_code;
	ubyte[2][2][2] motion_residual;
	ubyte[2] dmvector;
	uint coded_block_pattern;
	Block[12] blocks;

	this(Slice s)
	{
		this.s = s;
	}

	void parse(BitstreamReader bs)
	{
		int temp_incr = bs.read_mb_inc();

		while(temp_incr == 34)
		{
			this.incr += 33;
			temp_incr = bs.read_mb_inc();
		}

		this.incr += temp_incr;

		parse_modes(bs);

		if(p.quant)
		{
			this.quantiser_scale_code = cast(ubyte) bs.read_u(5);
		}

		if(p.motion_forward || (p.intra && s.ph.concealment_motion_vectors))
		{
			parse_motion_vectors(bs, 0);
		}

		if(p.motion_backward)
		{
			parse_motion_vectors(bs, 1);
		}

		if(p.intra && s.ph.concealment_motion_vectors)
		{
			enforce(bs.read_u1 == 1, "marker bit");
		}

		if(p.pattern)
		{
			parse_coded_block_pattern(bs);
		}

		for(ubyte i=0; i< block_count(); ++i)
		{
			parse_block(bs, i);
		}
	}

	ubyte block_count()
	{
		immutable ubyte[] table = [
			0, // should not happen
			6,
			8,
			12,
		];

		return table[s.ph.si.chroma_format];
	}

	void parse_motion_vectors(BitstreamReader bs, ubyte s)
	{
		if(predinfo.motion_vector_count == 1)
		{
			if(predinfo.mv_format == MvFormat.Field && predinfo.dmv != 1)
			{
				motion_vertical_field_select[0][s] = bs.read_bool;
			}

			parse_mv(bs, 0, s);
		}
		else
		{
			motion_vertical_field_select[0][s] = bs.read_bool;
			parse_mv(bs, 0, s);
			motion_vertical_field_select[1][s] = bs.read_bool;
			parse_mv(bs, 1, s);
		}
	}

	void parse_mv(BitstreamReader bs, ubyte r, ubyte s)
	{
		motion_code[r][s][0] = bs.read_mc;
		if(this.s.ph.f_code[s][0] != 1 && motion_code[r][s][0] != 0)
		{
			motion_residual[r][s][0] = bs.read_b(this.s.ph.f_code[s][0] - 1);
		}
		if(predinfo.dmv == 1)
		{
			dmvector[0] = bs.read_dmvector();
		}

		motion_code[r][s][1] = bs.read_mc;
		if(this.s.ph.f_code[s][1] != 1 && motion_code[r][s][1] != 0)
		{
			motion_residual[r][s][1] = bs.read_b(this.s.ph.f_code[s][1] - 1);
		}
		if(predinfo.dmv == 1)
		{
			dmvector[1] = bs.read_dmvector();
		}
	}

	void parse_coded_block_pattern(BitstreamReader bs)
	{
		coded_block_pattern = bs.read_cbp();
		if(s.ph.si.chroma_format == ChromaFormat.C422)
		{
			coded_block_pattern <<= 2;
			coded_block_pattern |= bs.read_u(2);
		}
		if(s.ph.si.chroma_format == ChromaFormat.C444)
		{
			coded_block_pattern <<= 6;
			coded_block_pattern |= bs.read_u(6);
		}
	}

	bool pattern_code(ubyte i)
	{
		if(p.pattern)
		{
			return cast(bool)(coded_block_pattern & (1 << (block_count() - 1 - i)));
		}
		else
		{
			return p.intra;
		}
	}

	void parse_block(BitstreamReader bs, ubyte i)
	{
		if(!pattern_code(i)) return;

		if(p.intra)
		{
			// TODO: optimize
			uint dc_size = bs.read_dc_size(i<4);
			short ddd = bs.read_u!short(dc_size);
			if(ddd >> (dc_size - 1))
			{
				ddd = cast(short) (ddd + 1 - (1 << dc_size));
			}
			blocks[i].coeffs[0] = ddd;
		}

		short run, level;
		int idx = p.intra;
		bool eob = !bs.read_dct(idx == 0, run, level, s.ph.intra_vlc_format);
		while(!eob)
		{
			//writefln("block(%d): rl: (%d, %d) idx: %d", i, run, level, idx);
			idx += run;
			blocks[i].coeffs[idx] = level;
			++idx;
			eob = !bs.read_dct(false, run, level, s.ph.intra_vlc_format);
		}
	}

	PredictionInfo predinfo()
	{
		if(s.ph.picture_structure == PictureStructure.Frame)
		{
			if(s.ph.frame_pred_frame_dct == 0)
				return frame_prediction_info[motion_type][0];
			else
				return frame_prediction_info[2][0]; // Frame-based
		}
		else
		{
			return field_prediction_info[motion_type][0];
		}
	}

	void parse_modes(BitstreamReader bs)
	{
		this.type = bs.read_mb_type(s.ph.picture_coding_type);
		this.p = mb_params[s.ph.picture_coding_type][this.type];

		if(this.p.spartial_temporal_weight_code_flag
			/* TODO: && spatial_temporal_weight_code_table_index != 00 */
		)
		{
			throw new Exception("spartial prediction is not implemented");
			//this.spartial_temporal_weight_code = bs.read_u(8);
		}

		if(this.p.motion_forward || this.p.motion_backward)
		{
			if(s.ph.picture_structure == PictureStructure.Frame)
			{
				if(s.ph.frame_pred_frame_dct == 0)
				{
					this.motion_type = bs.read_b(2);
				}
			}
			else
			{
				this.motion_type = bs.read_b(2);
			}
		}

		if(s.ph.picture_structure == PictureStructure.Frame
			&& s.ph.frame_pred_frame_dct == 0
			&& (this.p.intra || this.p.pattern)
			)
		{
			this.dct_type = bs.read_u1;
		}
	}

	void dump_block(int idx)
	{
		writefln("    block(%d):", idx);
		for(size_t i=0; i<8; ++i)
		{
			writef("        ");
			for(size_t j=0; j<8; ++j)
			{
				writef("%3d ", blocks[idx].coeffs[i*8+j]);
			}
			writefln("");
		}
	}

	void dump(bool with_blocks = false)
	{
		auto mb = this;

		writefln("macroblock:");
		writefln("    params   : %s", mb.p);
		writefln("    type     : %d", mb.type);
		writefln("    incr     : %d", mb.incr);

		if(p.quant)
		{
			writefln("    type     : %d", mb.quantiser_scale_code);
		}

		if(p.motion_forward || (p.intra && s.ph.concealment_motion_vectors))
		{
		}

		if(p.motion_backward)
		{
		}

		if(p.pattern)
		{
			writefln("    cbp      : %d", mb.coded_block_pattern);
		}

		if(with_blocks)
		{
			for(ubyte i=0; i< block_count(); ++i)
			{
				dump_block(i);
			}
		}
	}

	void dump2(int mba, bool with_blocks)
	{
		writefln("mb.incr: %d MBA: %d cbp: %d", incr, mba, coded_block_pattern);

		if(!with_blocks) return;

		for(ubyte bidx=0; bidx< block_count(); ++bidx)
		{
			writef("MBA #%d block #%d: ", mba, bidx);

			for(size_t i=0; i<8; ++i)
			{
				for(size_t j=0; j<8; ++j)
				{
					writef("%3d ", blocks[bidx].coeffs[i*8+j]);
				}
			}
			writeln();
		}

	}
}

struct MbParams
{
	bool quant;
	bool motion_forward;
	bool motion_backward;
	bool pattern;
	bool intra;
	bool spartial_temporal_weight_code_flag;
	uint permitted_spatial_temporal_weight_classes;

	string toString()
	{
		string s = "";

		if(quant) s ~= "quant,";
		if(motion_forward) s ~= "motion_forward,";
		if(motion_backward) s ~= "motion_backward,";
		if(pattern) s ~= "pattern,";
		if(intra) s ~= "intra,";
		if(spartial_temporal_weight_code_flag) s ~= "spartial_temporal_weight_code_flag,";

		if(s.length > 0)
			s = s[0..$-1];

		return s;
	}
}

struct PredictionInfo
{
	PredictionType type;
	ubyte motion_vector_count;
	MvFormat mv_format;
	bool dmv;
}

// Table 6-17
static immutable PredictionInfo[4][4] frame_prediction_info = [
	[
		{PredictionType.Frame, 1, MvFormat.Field, 0},
	],
	[
		{PredictionType.Field, 2, MvFormat.Field, 0},
		{PredictionType.Field, 2, MvFormat.Field, 0},
		{PredictionType.Field, 1, MvFormat.Field, 0},
		{PredictionType.Field, 1, MvFormat.Field, 0},
	],
	[
		{PredictionType.Frame, 1, MvFormat.Frame, 0},
		{PredictionType.Frame, 1, MvFormat.Frame, 0},
		{PredictionType.Frame, 1, MvFormat.Frame, 0},
		{PredictionType.Frame, 1, MvFormat.Frame, 0},
	],
	[
		{PredictionType.DualPrime, 1, MvFormat.Field, 1},
		{},
		{PredictionType.DualPrime, 1, MvFormat.Field, 1},
		{PredictionType.DualPrime, 1, MvFormat.Field, 1},
	],
];

// Table 6-18
static immutable PredictionInfo[2][4] field_prediction_info = [
	[
		{PredictionType.Field, 1, MvFormat.Field, 0},
	],
	[
		{PredictionType.Field, 1, MvFormat.Field, 0},
		{PredictionType.Field, 1, MvFormat.Field, 0},
	],
	[
		{PredictionType.Mc16x8, 2, MvFormat.Field, 0},
		{PredictionType.Mc16x8, 2, MvFormat.Field, 0},
	],
	[
		{PredictionType.DualPrime, 1, MvFormat.Field, 1},
	],
];

// Table B.2
immutable MbParams[] mb_params_I = [
	{0,0,0,0,1,0,0},
	{1,0,0,0,1,0,0},
];

// Table B.3
immutable MbParams[] mb_params_P = [
	{0,1,0,1,0,0,0},
	{0,0,0,1,0,0,0},
	{0,1,0,0,0,0,0},
	{0,0,0,0,1,0,0},
	{1,1,0,1,0,0,0},
	{1,0,0,1,0,0,0},
	{1,0,0,0,1,0,0},
];

// Table B.4
immutable MbParams[] mb_params_B = [
	{0,1,1,0,0,0,0},
	{0,1,1,1,0,0,0},
	{0,0,1,0,0,0,0},
	{0,0,1,1,0,0,0},
	{0,1,0,0,0,0,0},
	{0,1,0,1,0,0,0},
	{0,0,0,0,1,0,0},
	{1,1,1,1,0,0,0},
	{1,1,0,1,0,0,0},
	{1,0,1,1,0,0,0},
	{1,0,0,0,1,0,0},
];

// TODO:
// Table B.5-8


immutable MbParams[][] mb_params = [
	[],
	mb_params_I,
	mb_params_P,
	mb_params_B,
];