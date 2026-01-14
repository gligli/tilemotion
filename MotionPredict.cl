__constant int cColorCpns = 3;
__constant int cTileWidth = 8;
__constant int cTileDCTSize = cTileWidth * cTileWidth * cColorCpns;

unsigned int sqr(short x)
{
	return x * x;
}

unsigned int compareEuclideanDCTPtr(__global short * pa, __global short * pb)
{
	unsigned int res = 0;

	for(int i = cTileDCTSize / 8 - 1; i >= 0; --i)
	{
		res += sqr(*pa - *pb); ++pa; ++pb;
		res += sqr(*pa - *pb); ++pa; ++pb;
		res += sqr(*pa - *pb); ++pa; ++pb;
		res += sqr(*pa - *pb); ++pa; ++pb;
		res += sqr(*pa - *pb); ++pa; ++pb;
		res += sqr(*pa - *pb); ++pa; ++pb;
		res += sqr(*pa - *pb); ++pa; ++pb;
		res += sqr(*pa - *pb); ++pa; ++pb;
	}
	
	return res;
}

__kernel void MotionPredict(int screenWidth, int dx, int dy, int oxmn, int oymn, __global short * prevDCTs, __global short * curDCT, __global unsigned int * output)
{
	int ox = get_global_id(0);
	int oy = get_global_id(1);
	int ow = get_global_size(0);

	int yx = oy * (screenWidth - cTileWidth + 1) + ox;

  unsigned int err = compareEuclideanDCTPtr(curDCT, &prevDCTs[yx * cTileDCTSize]);

	// apply a penalty of the manhattan distance to the center
	// rationale: slightly favoring the center in case of ties improves compressibility
	err += abs_diff(ox, dx) + abs_diff(oy, dy);
	
	output[(oy - oymn) * ow + (ox - oxmn)] = err;
}
