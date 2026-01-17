__constant int cTileWidthBits = 3;
__constant int cColorCpns = 3;

__constant int cTileWidth = 1 << cTileWidthBits;
__constant int cTileDCTSize = cTileWidth * cTileWidth * cColorCpns;

struct xyErr_s
{
  uint err;
  int x;
  int y;
  uint dummy;
};

bool quickTestEuclideanDCT(__global short * pa, __global short * pb, uint min_dist)
{
  int8 va = convert_int8(vload8(0x00, pa));
  int8 vb = convert_int8(vload8(0x00, pb));

  int8 vd = va - vb;

  int8 vm = vd * vd;

  return vm.s0 + vm.s1 + vm.s2 + vm.s3 + vm.s4 + vm.s5 + vm.s6 + vm.s7 < min_dist;
}

unsigned int compareEuclideanDCT(__global short * pa, __global short * pb)
{
  unsigned int res = 0;

  for (int i = 0; i < cTileDCTSize / (12 /* unroll */ * 8 /* vector */); ++i)
  {
    int8 va0 = convert_int8(vload8(0x00, pa));
    int8 vb0 = convert_int8(vload8(0x00, pb));

    int8 va1 = convert_int8(vload8(0x01, pa));
    int8 vb1 = convert_int8(vload8(0x01, pb));

    int8 va2 = convert_int8(vload8(0x02, pa));
    int8 vb2 = convert_int8(vload8(0x02, pb));

    int8 va3 = convert_int8(vload8(0x03, pa));
    int8 vb3 = convert_int8(vload8(0x03, pb));

    int8 va4 = convert_int8(vload8(0x04, pa));
    int8 vb4 = convert_int8(vload8(0x04, pb));

    int8 va5 = convert_int8(vload8(0x05, pa));
    int8 vb5 = convert_int8(vload8(0x05, pb));

    int8 va6 = convert_int8(vload8(0x06, pa));
    int8 vb6 = convert_int8(vload8(0x06, pb));

    int8 va7 = convert_int8(vload8(0x07, pa));
    int8 vb7 = convert_int8(vload8(0x07, pb));

    int8 va8 = convert_int8(vload8(0x08, pa));
    int8 vb8 = convert_int8(vload8(0x08, pb));

    int8 va9 = convert_int8(vload8(0x09, pa));
    int8 vb9 = convert_int8(vload8(0x09, pb));

    int8 vaa = convert_int8(vload8(0x0a, pa));
    int8 vba = convert_int8(vload8(0x0a, pb));

    int8 vab = convert_int8(vload8(0x0b, pa));
    int8 vbb = convert_int8(vload8(0x0b, pb));

    int8 vd0 = va0 - vb0;
    int8 vd1 = va1 - vb1;
    int8 vd2 = va2 - vb2;
    int8 vd3 = va3 - vb3;
    int8 vd4 = va4 - vb4;
    int8 vd5 = va5 - vb5;
    int8 vd6 = va6 - vb6;
    int8 vd7 = va7 - vb7;
    int8 vd8 = va8 - vb8;
    int8 vd9 = va9 - vb9;
    int8 vda = vaa - vba;
    int8 vdb = vab - vbb;

    int8 vm0 = vd0 * vd0;
    int8 vm1 = vd1 * vd1;
    int8 vm2 = vd2 * vd2;
    int8 vm3 = vd3 * vd3;
    int8 vm4 = vd4 * vd4;
    int8 vm5 = vd5 * vd5;
    int8 vm6 = vd6 * vd6;
    int8 vm7 = vd7 * vd7;
    int8 vm8 = vd8 * vd8;
    int8 vm9 = vd9 * vd9;
    int8 vma = vda * vda;
    int8 vmb = vdb * vdb;

    int8 vh = vm0 + vm1 + vm2 + vm3 + vm4 + vm5 + vm6 + vm7 + vm8 + vm9 + vma + vmb;

    res += vh.s0 + vh.s1 + vh.s2 + vh.s3 + vh.s4 + vh.s5 + vh.s6 + vh.s7;

    pa += 12 * 8;
    pb += 12 * 8;
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

  uint bestErr = (uint) -1;
  int bestX = -1;
  int bestY = -1;

  __global short * curPtr = &plainDCTs[sxy * cTileDCTSize];
  prefetch(curPtr, cTileDCTSize);

  for (int oy = oymn; oy <= oymx; ++oy)
  {
    int yx = oy * (screenWidth - cTileWidth + 1) + oxmn;

    __global short * prevPtr = &prevDCTs[yx * cTileDCTSize];
    prefetch(prevPtr, cTileDCTSize);

    for (int ox = oxmn; ox <= oxmx; ++ox)
    {
      if (quickTestEuclideanDCT(curPtr, prevPtr, bestErr))
      {
        uint err = compareEuclideanDCT(curPtr, prevPtr);

        // apply a penalty of the manhattan distance to the center
        // rationale: slightly favoring the center in case of ties improves compressibility
        err += abs_diff(ox, dx) + abs_diff(oy, dy);

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
