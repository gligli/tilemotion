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

void fetchDCT(__global short * pa, int16 * out)
{
  prefetch(pa, cTileDCTSize);

  out[0x00] = convert_int16(vload16(0x00, pa));
  out[0x01] = convert_int16(vload16(0x01, pa));
  out[0x02] = convert_int16(vload16(0x02, pa));
  out[0x03] = convert_int16(vload16(0x03, pa));
  out[0x04] = convert_int16(vload16(0x04, pa));
  out[0x05] = convert_int16(vload16(0x05, pa));
  out[0x06] = convert_int16(vload16(0x06, pa));
  out[0x07] = convert_int16(vload16(0x07, pa));
  out[0x08] = convert_int16(vload16(0x08, pa));
  out[0x09] = convert_int16(vload16(0x09, pa));
  out[0x0a] = convert_int16(vload16(0x0a, pa));
  out[0x0b] = convert_int16(vload16(0x0b, pa));
}

int8 fetchDCTQuickTest(__global short * pa)
{
  return convert_int8(vload8(0x00, pa));
}

bool quickTestEuclideanDCT(int8 va, __global short * pb, uint min_dist)
{
  int8 vb = convert_int8(vload8(0x00, pb));

  int8 vd = va - vb;

  int8 vm = vd * vd;

  return vm.s0 + vm.s1 + vm.s2 + vm.s3 + vm.s4 + vm.s5 + vm.s6 + vm.s7 < min_dist;
}

unsigned int compareEuclideanDCT(int16 * va, __global short * pb)
{
  prefetch(pb, cTileDCTSize);

  int16 vb0 = convert_int16(vload16(0x00, pb));
  int16 vb1 = convert_int16(vload16(0x01, pb));
  int16 vb2 = convert_int16(vload16(0x02, pb));
  int16 vb3 = convert_int16(vload16(0x03, pb));
  int16 vb4 = convert_int16(vload16(0x04, pb));
  int16 vb5 = convert_int16(vload16(0x05, pb));
  int16 vb6 = convert_int16(vload16(0x06, pb));
  int16 vb7 = convert_int16(vload16(0x07, pb));
  int16 vb8 = convert_int16(vload16(0x08, pb));
  int16 vb9 = convert_int16(vload16(0x09, pb));
  int16 vba = convert_int16(vload16(0x0a, pb));
  int16 vbb = convert_int16(vload16(0x0b, pb));

  int16 vd0 = va[0x00] - vb0;
  int16 vd1 = va[0x01] - vb1;
  int16 vd2 = va[0x02] - vb2;
  int16 vd3 = va[0x03] - vb3;
  int16 vd4 = va[0x04] - vb4;
  int16 vd5 = va[0x05] - vb5;
  int16 vd6 = va[0x06] - vb6;
  int16 vd7 = va[0x07] - vb7;
  int16 vd8 = va[0x08] - vb8;
  int16 vd9 = va[0x09] - vb9;
  int16 vda = va[0x0a] - vba;
  int16 vdb = va[0x0b] - vbb;

  int16 vm0 = vd0 * vd0;
  int16 vm1 = vd1 * vd1;
  int16 vm2 = vd2 * vd2;
  int16 vm3 = vd3 * vd3;
  int16 vm4 = vd4 * vd4;
  int16 vm5 = vd5 * vd5;
  int16 vm6 = vd6 * vd6;
  int16 vm7 = vd7 * vd7;
  int16 vm8 = vd8 * vd8;
  int16 vm9 = vd9 * vd9;
  int16 vma = vda * vda;
  int16 vmb = vdb * vdb;

  int16 vh = vm0 + vm1 + vm2 + vm3 + vm4 + vm5 + vm6 + vm7 + vm8 + vm9 + vma + vmb;

  return vh.s0 + vh.s1 + vh.s2 + vh.s3 + vh.s4 + vh.s5 + vh.s6 + vh.s7 + vh.s8 + vh.s9 + vh.sa + vh.sb + vh.sc + vh.sd + vh.se + vh.sf;
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
  int16 curDCT[12]; fetchDCT(curPtr, curDCT);
  int8 curDCTQuickTest = fetchDCTQuickTest(curPtr);

  for (int oy = oymn; oy <= oymx; ++oy)
  {
    int yx = oy * (screenWidth - cTileWidth + 1) + oxmn;

    __global short * prevPtr = &prevDCTs[yx * cTileDCTSize];

    for (int ox = oxmn; ox <= oxmx; ++ox)
    {
      if (quickTestEuclideanDCT(curDCTQuickTest, prevPtr, bestErr))
      {
        uint err = compareEuclideanDCT(curDCT, prevPtr);

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
