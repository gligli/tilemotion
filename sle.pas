{$TYPEDADDRESS OFF}

{
    This file is part of the Numlib package.
    Copyright (c) 1986-2000 by
     Kees van Ginneken, Wil Kortsmit and Loek van Reij of the
     Computational centre of the Eindhoven University of Technology

    FPC port Code          by Marco van de Voort (marco@freepascal.org)
             documentation by Michael van Canneyt (Michael@freepascal.org)

    !! modifies randseed, might not exactly work as TP version!!!

    Solve set of linear equations of the type Ax=b, for generic, and a
    variety of special matrices.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{Solve set of linear equations of the type Ax=b, for generic, and a variety of
special matrices.
One (generic) function for overdetermined sets of this kind : slegls

overdetermined are sets that look like this: (I don't know if I
translated "overdetermined" right)

    6   1  2  3     9
    3   9  3  4     2
   17  27 42 15    62
   17  27 42 15    61

The two bottom rows look much alike, which introduces a big uncertainty in the
result, therefore these matrices need special treatment.

All procedures have similar procedure with a "L" appended to the name. We
didn't receive docs for those procedures. If you know what the difference is,
please mail us }

Unit sle;
interface

// gligli Single version with only slegls

type
  ArbFloat    = Single;
  ArbInt      = LONGINT;

const
  highestfloatelement = High(ArbInt) div SizeOf(ArbFloat);
  highestintelement = High(ArbInt) div SizeOf(ArbInt);
  highestptrelement = High(ArbInt) div SizeOf(Pointer);

type
  arfloat1   = array[1..highestfloatelement] of ArbFloat;
  arint1     = array[1..highestintelement] of ArbInt;
  ar2dr1     = array[1..highestptrelement] of ^arfloat1;
  par2dr1    = ^ar2dr1;

{solve for overdetermined matrices, see unit comments}
Procedure slegls(Var a: ArbFloat; m, n, rwidtha: ArbInt; Var b, x: ArbFloat;
                 Var term: ArbInt);

implementation

Uses DSL,MDT;

{Here originally stood an exact copy of mdtgtr from unit mdt}
{Here originally stood an exact copy of dslgtr from unit DSL}

Procedure decomp(Var qr: ArbFloat; m, n, rwidthq: ArbInt; Var alpha: ArbFloat;
                 Var pivot, term: ArbInt);

Var  i, j, jbar, k, ns, ii        : ArbInt;
     beta, sigma, alphak, qrkk, s : ArbFloat;
     pqr, pal, y, sum             : ^arfloat1;
     piv                          : ^arint1;

Begin
  term := 1;
  pqr := @qr;
  pal := @alpha;
  piv := @pivot;
  ns := n*sizeof(ArbFloat);
  getmem(y, ns);
  getmem(sum, ns);
  For j:=1 To n Do
    Begin
      s := 0;
      For i:=1 To m Do
        s := s+sqr(pqr^[(i-1)*rwidthq+j]);
      sum^[j] := s;
      piv^[j] := j
    End; {j}
  For k:=1 To n Do
    Begin
      sigma := sum^[k];
      jbar := k;
      For j:=k+1 To n Do
        If sigma < sum^[j] Then
          Begin
            sigma := sum^[j];
           jbar := j
          End;
      If jbar <> k
       Then
        Begin
          i := piv^[k];
          piv^[k] := piv^[jbar];
          piv^[jbar] := i;
          sum^[jbar] := sum^[k];
          sum^[k] := sigma;
          For i:=1 To m Do
            Begin
              ii := (i-1)*rwidthq;
              sigma := pqr^[ii+k];
              pqr^[ii+k] := pqr^[ii+jbar];
              pqr^[ii+jbar] := sigma
            End; {i}
        End; {column interchange}
      sigma := 0;
      For i:=k To m Do
        sigma := sigma+sqr(pqr^[(i-1)*rwidthq+k]);
      If sigma=0 Then
        Begin
          term := 2;
          freemem(y, ns);
          freemem(sum, ns);
          exit
        End;
      qrkk := pqr^[(k-1)*rwidthq+k];
      If qrkk < 0 Then
        alphak := sqrt(sigma)
      Else
        alphak := -sqrt(sigma);
      pal^[k] := alphak;
      beta := 1/(sigma-qrkk*alphak);
      pqr^[(k-1)*rwidthq+k] := qrkk-alphak;
      For j:=k+1 To n Do
        Begin
          s := 0;
          For i:=k To m Do
            Begin
              ii := (i-1)*rwidthq;
              s := s+pqr^[ii+k]*pqr^[ii+j]
            End; {i}
          y^[j] := beta*s
        End; {j}
      For j:=k+1 To n Do
        Begin
          For i:=k To m Do
            Begin
              ii := (i-1)*rwidthq;
              pqr^[ii+j] := pqr^[ii+j]-pqr^[ii+k]*y^[j]
            End; {i}
          sum^[j] := sum^[j]-sqr(pqr^[(k-1)*rwidthq+j])
        End {j}
    End; {k}
  freemem(y, ns);
 freemem(sum, ns);
End; {decomp}

Procedure decomp1(Var qr1; m, n: ArbInt; Var alpha1: ArbFloat;
                  Var pivot1, term: ArbInt);

Var             i, j, jbar, k, ns : ArbInt;
     beta, sigma, alphak, qrkk, s : ArbFloat;
     qr                           : ar2dr1 absolute qr1;
     alpha                        : arfloat1 absolute alpha1;
     pivot                        : arint1 absolute pivot1;
     y, sum                       : ^arfloat1;
Begin
  term := 1;
  ns := n*sizeof(ArbFloat);
  getmem(y, ns);
 getmem(sum, ns);
  For j:=1 To n Do
    Begin
      s := 0;
      For i:=1 To m Do
       s := s+sqr(qr[i]^[j]);
      sum^[j] := s;
     pivot[j] := j
    End; {j}
  For k:=1 To n Do
    Begin
      sigma := sum^[k];
     jbar := k;
      For j:=k+1 To n Do
        If sigma < sum^[j]
         Then
          Begin
            sigma := sum^[j];
           jbar := j
          End;
      If jbar <> k
       Then
        Begin
          i := pivot[k];
         pivot[k] := pivot[jbar];
         pivot[jbar] := i;
          sum^[jbar] := sum^[k];
         sum^[k] := sigma;
          For i:=1 To m Do
            Begin
              sigma := qr[i]^[k];
             qr[i]^[k] := qr[i]^[jbar];
              qr[i]^[jbar] := sigma
            End; {i}
        End; {column interchange}
      sigma := 0;
      For i:=k To m Do
       sigma := sigma+sqr(qr[i]^[k]);
      If sigma=0
       Then
        Begin
          term := 2;
         freemem(y, ns);
         freemem(sum, ns);
         exit
        End;
      qrkk := qr[k]^[k];
      If qrkk < 0 Then alphak := sqrt(sigma)
     Else alphak := -sqrt(sigma);
      alpha[k] := alphak;
      beta := 1/(sigma-qrkk*alphak);
      qr[k]^[k] := qrkk-alphak;
      For j:=k+1 To n Do
        Begin
          s := 0;
         For i:=k To m Do
          s := s+qr[i]^[k]*qr[i]^[j];
         y^[j] := beta*s
        End; {j}
      For j:=k+1 To n Do
        Begin
          For i:=k To m Do
           qr[i]^[j] := qr[i]^[j]-qr[i]^[k]*y^[j];
          sum^[j] := sum^[j]-sqr(qr[k]^[j])
        End {j}
    End; {k}
  freemem(y, ns);
 freemem(sum, ns);
End; {decomp1}

Procedure solve(Var qr: ArbFloat; m, n, rwidthq: ArbInt; Var alpha: ArbFloat;
                Var pivot: ArbInt; Var r, y: ArbFloat);

Var    i, j, ii            : ArbInt;
       gamma, s            : ArbFloat;
       pqr, pal, pr, py, z : ^arfloat1;
       piv                 : ^arint1;
Begin
  pqr := @qr;
  pal := @alpha;
  piv := @pivot;
  pr := @r;
  py := @y;
  getmem(z, n*sizeof(ArbFloat));
  For j:=1 To n Do
    Begin
      gamma := 0;
      For i:=j To m Do
        gamma := gamma+pqr^[(i-1)*rwidthq+j]*pr^[i];
      gamma := gamma/(pal^[j]*pqr^[(j-1)*rwidthq+j]);
      For i:=j To m Do
        pr^[i] := pr^[i]+gamma*pqr^[(i-1)*rwidthq+j]
    End; {j}
  z^[n] := pr^[n]/pal^[n];
  For i:=n-1 Downto 1 Do
    Begin
      s := pr^[i];
      ii := (i-1)*rwidthq;
      For j:=i+1 To n Do
        s := s-pqr^[ii+j]*z^[j];
      z^[i] := s/pal^[i]
    End; {i}
  For i:=1 To n Do
    py^[piv^[i]] := z^[i];
  freemem(z, n*sizeof(ArbFloat));
End; {solve}

Procedure solve1(Var qr1; m, n: ArbInt; Var alpha1: ArbFloat;
                 Var pivot1: ArbInt; Var r1, y1: ArbFloat);

Var    i, j                : ArbInt;
       gamma, s            : ArbFloat;
       qr                  : ar2dr1 absolute qr1;
       alpha               : arfloat1 absolute alpha1;
       r                   : arfloat1 absolute r1;
       y                   : arfloat1 absolute y1;
       pivot               : arint1 absolute pivot1;
       z                   : ^arfloat1;
Begin
  getmem(z, n*sizeof(ArbFloat));
  For j:=1 To n Do
    Begin
      gamma := 0;
      For i:=j To m Do
       gamma := gamma+qr[i]^[j]*r[i];
      gamma := gamma/(alpha[j]*qr[j]^[j]);
      For i:=j To m Do
       r[i] := r[i]+gamma*qr[i]^[j]
    End; {j}
  z^[n] := r[n]/alpha[n];
  For i:=n-1 Downto 1 Do
    Begin
      s := r[i];
      For j:=i+1 To n Do
       s := s-qr[i]^[j]*z^[j];
      z^[i] := s/alpha[i]
    End; {i}
  For i:=1 To n Do
   y[pivot[i]] := z^[i];
  freemem(z, n*sizeof(ArbFloat));
End; {solve1}

Procedure slegls(Var a: ArbFloat; m, n, rwidtha: ArbInt; Var b, x: ArbFloat;
                 Var term: ArbInt);

Var     i, j, ns, ms, ii                : ArbInt;
        normy0, norme1, s       : ArbFloat;
        pa, pb, px, qr, alpha, e, y, r  : ^arfloat1;
        pivot                           : ^arint1;
Begin
  If (n<1) Or (m<n)
   Then
    Begin
      term := 3;
     exit
    End;
  pa := @a;
 pb := @b;
 px := @x;
  ns := n*sizeof(ArbFloat);
 ms := m*sizeof(ArbFloat);
  getmem(qr, m*ns);
 getmem(alpha, ns);
 getmem(e, ns);
 getmem(y, ns);
  getmem(r, m*sizeof(ArbFloat));
 getmem(pivot, n*sizeof(ArbInt));
  For i:=1 To m Do
    move(pa^[(i-1)*rwidtha+1], qr^[(i-1)*n+1], ns);
  decomp(qr^[1], m, n, n, alpha^[1], pivot^[1], term);
  If term=2
   Then
    Begin
      freemem(qr, m*ns);
     freemem(alpha, ns);
     freemem(e, ns);
     freemem(y, ns);
      freemem(r, m*sizeof(ArbFloat));
     freemem(pivot, n*sizeof(ArbInt));
      exit
    End;
  move(pb^[1], r^[1], ms);
  solve(qr^[1], m, n, n, alpha^[1], pivot^[1], r^[1], y^[1]);
  For i:=1 To m Do
    Begin
      s := pb^[i];
     ii := (i-1)*rwidtha;
      For j:=1 To n Do
        s := s-pa^[ii+j]*y^[j];
      r^[i] := s
    End; {i}
  solve(qr^[1], m, n, n, alpha^[1], pivot^[1], r^[1], e^[1]);
  normy0 := 0;
 norme1 := 0;
  For i:=1 To n Do
    Begin
      normy0 := normy0+sqr(y^[i]);
     norme1 := norme1+sqr(e^[i])
    End; {i}
  If norme1 > 0.0625*normy0
   Then
    Begin
      term := 2;
      freemem(qr, m*ns);
     freemem(alpha, ns);
     freemem(e, ns);
     freemem(y, ns);
      freemem(r, m*sizeof(ArbFloat));
     freemem(pivot, n*sizeof(ArbInt));
      exit
    End;
  For i:=1 To n Do
    px^[i] := y^[i];
  freemem(qr, m*ns);
 freemem(alpha, ns);
 freemem(e, ns);
 freemem(y, ns);
  freemem(r, m*sizeof(ArbFloat));
 freemem(pivot, n*sizeof(ArbInt));
End; {slegls}

Begin
  {$ifdef fixate_random}
  randseed := 12345
  {$endif}
End.
