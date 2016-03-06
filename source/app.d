
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

		for(size_t i=0; i<f.width*f.height / 2; ++i)
		{
			buf[f.width*f.height + i] = 128;
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
