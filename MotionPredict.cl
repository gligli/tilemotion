__constant int cTileWidthBits = 3;
__constant int cColorCpns = 3;

__constant int cTileWidth = 1 << cTileWidthBits;
__constant int cTileDCTSize = cTileWidth * cTileWidth * cColorCpns;

struct xyErr_s
{
  unsigned int err;
  int x;
  int y;
  unsigned int dummy;
};

inline unsigned int sqr(short x)
{
  return x * x;
}

bool quickTestEuclideanDCT(__global short * pa, __global short * pb, unsigned int min_dist)
{
  bool res = sqr(pa[0] - pb[0]) + sqr(pa[1] - pb[1]) + sqr(pa[2] - pb[2]) + sqr(pa[3] - pb[3]) +
             sqr(pa[4] - pb[4]) + sqr(pa[5] - pb[5]) + sqr(pa[6] - pb[6]) + sqr(pa[7] - pb[7]) < min_dist;

  return res;
}

unsigned int compareEuclideanDCT(__global short * pa, __global short * pb)
{
  unsigned int res = 0;

  for(int i = cTileDCTSize / 8 - 1; i >= 0; --i)
  {
    res += sqr(pa[0] - pb[0]);
    res += sqr(pa[1] - pb[1]);
    res += sqr(pa[2] - pb[2]);
    res += sqr(pa[3] - pb[3]);
    res += sqr(pa[4] - pb[4]);
    res += sqr(pa[5] - pb[5]);
    res += sqr(pa[6] - pb[6]);
    res += sqr(pa[7] - pb[7]);
    pa += 8;
    pb += 8;
  }
  
  return res;
}

__kernel void MotionPredict(__global struct xyErr_s * outErrs, __global short * prevDCTs, __global short * plainDCTs, int radius, int screenWidth, int screenHeight)
{
  int sx = get_global_id(0);
  int sy = get_global_id(1);
  int tmWidth = get_global_size(0);
  int tmHeight = get_global_size(1);

  int sxy = sy * tmWidth + sx;
  int dx = sx << cTileWidthBits;
  int dy = sy << cTileWidthBits;

  int oxmn = max(0, dx - radius - 1);
  int oymn = max(0, dy - radius - 1);
  int oxmx = min(screenWidth - cTileWidth, dx + radius);
  int oymx = min(screenHeight - cTileWidth, dy + radius);

  unsigned int bestErr = (unsigned int) -1;
  int bestX = -1;
  int bestY = -1;

  __global short * curPtr = &plainDCTs[sxy * cTileDCTSize];

  for (int oy = oymn; oy <= oymx; ++oy)
  {
    int yx = oy * (screenWidth - cTileWidth + 1) + oxmn;
    __global short * prevPtr = &prevDCTs[yx * cTileDCTSize];

    for (int ox = oxmn; ox <= oxmx; ++ox)
    {
      if (quickTestEuclideanDCT(curPtr, prevPtr, bestErr))
      {
        unsigned int err = compareEuclideanDCT(curPtr, prevPtr);

        // apply a penalty of the manhattan distance to the center
        // rationale: slightly favoring the center in case of ties improves compressibility
        err += abs(ox - dx) + abs(oy - dy);

        if (err < bestErr)
        {
          bestErr = err;
          bestX = ox;
          bestY = oy;
        }
      }
 
      prevPtr += cTileDCTSize;
    }
  }

  outErrs[sxy].err = bestErr;
  outErrs[sxy].x = bestX - dx;
  outErrs[sxy].y = bestY - dy;
}
