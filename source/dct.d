
module dct;

import std.math;
import std.algorithm;
import math;

ref const(T[N][N]) DCT_MATRIX(T, uint N)()
{
	static T[N][N] instance;
	static bool initialized = false;

	auto C(uint k){ return (k == 0) ? 1.0/SQRT2: 1;}

	if(!initialized)
	{
		foreach(x; 0..N)
		{
			foreach(k; 0..N)
			{
				instance[x][k] = C(k) * cos((x + 0.5) / N * k * PI);
			}
		}

		initialized = true;
	}

	return instance;
}

void idct_1d(uint N,I,O)(I[] block, O[] rec, uint stride)
{
	const N2 = 2 * N;

	for(uint i=0; i<N; ++i)
	{
		O sum = 0;

		for(uint k=0; k<N; ++k)
		{
			sum += block[k * stride]
				//* C(k) * mycos((i + 0.5) / N * k * PI);
				 * DCT_MATRIX!(O,N)()[i][k];
		}

		rec[i * stride] = sum * sqrt(2.0 / N);
	}
}

void idct_2d(uint N)(ref short[N*N] block)
{
	real[N*N] rec;
	real[N*N] rec2;

	// rows
	for(uint i=0; i<N; ++i)
	{
		idct_1d!N(block[i*N ..(i+1)*N], rec[i*N ..(i+1)*N], 1);
	}

	// columns
	for(uint j=0; j<N; ++j)
	{
		idct_1d!N(rec[j..$], rec2[j..$], N);
	}

	for(uint i=0; i<N*N; ++i)
	{
		block[i] = cast(short) round(rec2[i]);
	}
}

void idct_annexA(ref short[64] block)
{
	idct_2d!8(block);
	foreach(i, v; block)
	{
		block[i] = saturate!(short,-256,255)(v);
	}
}

real norm(V,U)(V[] v, U[] u)
{
	real sum = 0;
	for(size_t i=0; i<v.length; ++i)
	{
		auto t = v[i] - u[i];
		sum += t*t;
	}

	return sqrt(sum) / v.length;
}

real norm(V)(V[] v)
{
	real sum = 0;
	for(size_t i=0; i<v.length; ++i)
	{
		sum += v[i] * v[i];
	}

	return sum;
}

unittest // check DC
{
	short[8] block;
	real[8] rec;
	auto reference = new real[8];

	block[0] = 8;
	fill(reference, 8.0/sqrt(8.0));

	idct_1d!8(block, rec, 1);

	auto err = norm(rec, reference);
	assert(err < 10e-5);
}

unittest // check Parseval's identity
{
	import std.random;

	const N = 8;

	foreach(i; 0..100)
	{
		auto block = uniformDistribution(N);
		real[N] rec;

		idct_1d!N(block, rec, 1);

		assert(abs(norm(block) - norm(rec)) < 10e-5);
	}
}

unittest // check DC 2D
{
	const N2 = 64;
	short[N2] block;
	auto reference = new real[N2];

	block[0] = 64;
	fill(reference, 8.0);
	auto orig = block;

	idct_2d!8(block);

	auto err = norm(block, reference);
	assert(err < 10e-5);
}
