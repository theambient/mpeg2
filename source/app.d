
import std.stdio;
import std.exception;
import decoder;

class App
{
	void run(string[] args)
	{
		enforce(args.length == 3, "usage: <input-file> <output-file>");

		string input_file = args[1];
		string output_file = args[2];

		out_fd = File(output_file, "wb");

		auto decoder = new Decoder(input_file);

		int cnt = 0;
		for(Frame f = decoder.decode(); f !is null && cnt < 1; f = decoder.decode())
		{
			writefln("decoded pic #%d", cnt);
			dump_frame(f);
			++cnt;
		}

		writefln("decoded %d frames", cnt);
	}

	void dump_frame(Frame f)
	{
		auto buf = new ubyte[f.width*f.height + f.width*f.height / 2];
		for(size_t i=0; i<f.width*f.height; ++i)
		{
			buf[i] = cast(ubyte)f.planes[0][i % f.width, i / f.width];
		}

		foreach(cc; 1..3)
		{
			auto base = f.width*f.height + (cc == 1?0:f.width*f.height / 4);

			for(size_t i=0; i<f.height / 2; ++i)
			{
				for(size_t j=0; j<f.width / 2; ++j)
				{
					auto v = (0L
						+ f.planes[cc][2*j, 2*i]
						+ f.planes[cc][2*j + 1, 2*i]
						+ f.planes[cc][2*j, 2*i + 1]
						+ f.planes[cc][2*j + 1, 2*i + 1]
						) / 4;

					buf[base + i * f.width / 2 + j] = cast(ubyte) v;
				}
			}
		}

		out_fd.rawWrite(buf);
	}

	private File out_fd;
}

void main(string[] args)
{
	auto app = new App;
	app.run(args);
}
