module lang::webassembly::Float

import lang::webassembly::FloatSyntax;
import ParseTree;
import Exception;
import String;
import util::Math;
import IO; // temp

data Float = fval( real r )
           | canonical_nan( )
           // According to the spec, no distinction is made between the "payload" of a signalling NaN
           // therefore there is no need to represent it
           | arithmetic_nan( )
           | positive_infinity( )
           | negative_infinity( )
           // This "cheat" is introduced. As no distinction is made between -0 and 0
           // -1/-0 = inf. -1/0 = -inf. This would otherwise be inconsistent.
           // it equals both -inf and +inf
           | arbitrary_infinity( )
           ;

Float Float_zero( ) = fval( 0.0 );

Float toFloat( str s ) {
  FN tree = parse( #FN, s );
  
  switch ( tree ) {
  case (FN)`<SN sn>`: return fval( toReal( toInt( sn ) ) ); // this is a normal decimal/hexadecimal integer
  case (FN)`-inf`: return negative_infinity( );
  case (FN)`+inf`: return positive_infinity( );
  case (FN)`inf`: return positive_infinity( );
  case (FN)`<Sign _>nan`: return canonical_nan( );
  case (FN)`<Sign _><ArithmeticNan _>`: return arithmetic_nan( );
  case (FN)`+<FNMag x>`: return toFloat( x );
  case (FN)`<FNMag x>`: return toFloat( x );
  case (FN)`-<FNMag x>`: {
    if ( fval( v ) := toFloat( x ) ) {
      return fval( -v );
    }
  }
  };
  
  println( "Failed to parse Float" );
  return arithmetic_nan( );
}

int toInt( SN sn ) = toInt( replaceAll( "<sn>", "_", "" ) );

Float toFloat( (FNMag)`<Float f>` ) = fval( toReal( replaceAll( "<f>", "_", "" ) ) );
Float toFloat( (FNMag)`0x<HexNum n>.<HexFrac f>` ) {
  magnitude = toReal( n ) + toFrac( f );
  return fval( magnitude );
}
Float toFloat( (FNMag)`0x<HexNum n>P<Sign s><Num p>` ) = toFloat( (FNMag)`0x<HexNum n>p<Sign s><Num p>` );
Float toFloat( (FNMag)`0x<HexNum n>p<Sign s><Num p>` ) {
  magnitude = toReal( n );
  power = toInt( replaceAll( "<s><p>", "_", "" ) );
  return fval( applyPower( magnitude, power ) );
}
Float toFloat( (FNMag)`0x<HexNum n>.<HexFrac f>P<Sign s><Num p>` ) = toFloat( (FNMag)`0x<HexNum n>.<HexFrac f>p<Sign s><Num p>` );
Float toFloat( (FNMag)`0x<HexNum n>.<HexFrac f>p<Sign s><Num p>` ) {
  magnitude = toReal( n ) + toFrac( f );
  power = toInt( replaceAll( "<s><p>", "_", "" ) );
  return fval( applyPower( magnitude, power ) );
}

real toReal( HexNum n ) = toReal( toInt( replaceAll( "0x<n>", "_", "" ) ) );

// This function is introduced to avoid rounding errors from "magnitude * pow( 2.0, power )"
real applyPower( real magnitude, int power ) {
  if ( power > 0 ) {
    for ( i <- [0..power] ) {
      magnitude = magnitude * 2;
    }
  } else if ( power < 0 ) {
    for ( i <- [0..-power] ) {
      magnitude = magnitude / 2;
    }
  }
  return magnitude;
}

// This function is introduced to avoid rounding errors from "f / pow(16.0, size(f))"
real toFrac( HexFrac f )
  = ( size( fStr ) == 0 ? 0.0 : toFrac( split( "", fStr ) ) )
  when fStr := replaceAll( "<f>", "_", "" );
real toFrac( list[str] x:[c, *L] ) = ( 1.0 / 16.0 ) * ( toReal( toInt( "0x<c>" ) ) + toFrac( L ) );
real toFrac( list[str] x:[] ) = 0.0;

// These operators are not formally implemented following the spec
//   mainly done intuitively, while trying to pass the test cases.

private bool isPositive( fval( v ) ) = ( v > 0 );
private bool isPositive( positive_infinity( ) ) = true;
private bool isPositive( Float f ) = false;

private Float flipSign( positive_infinity( ) ) = negative_infinity( );
private Float flipSign( negative_infinity( ) ) = positive_infinity( );
private Float flipSign( fval( v ) ) = fval( -v );
private Float flipSign( Float f ) = f;

// copies f2's sign to f1
Float fcopysign( Float f1, Float f2 ) {
  if ( isPositive( f1 ) != isPositive( f2 ) ) {
    return flipSign( f1 );
  } else {
    return f1;
  }
}

Float truncf( Float f ) {
  if ( fval( v ) := f ) {
    int ival = toInt( v );
    if ( ival == 0 ) {
      return fval( f >= 0 ? 0.0 : -0.0 );
    } else {
      return fval( toReal( ival ) );
    }
  } else {
    return f;
  }
}

Float fnearest( Float f ) {
  if ( fval( v ) := f ) {
    return fval( fnearest( f ) );
  } else {
    return f;
  }
}

Float min( negative_infinity( ), _ ) = negative_infinity( );
Float min( _, negative_infinity( ) ) = negative_infinity( );
Float min( a, positive_infinity( ) ) = a;
Float min( positive_infinity( ), a ) = a;
Float min( canonical_nan( ), _ ) = canonical_nan( );
Float min( _, canonical_nan( ) ) = canonical_nan( );
Float min( arithmetic_nan( ), _ ) = arithmetic_nan( );
Float min( _, arithmetic_nan( ) ) = arithmetic_nan( );
Float min( fval( a ), fval( b ) ) = fval( min( a, b ) );

Float max( positive_infinity( ), _ ) = positive_infinity( );
Float max( _, positive_infinity( ) ) = positive_infinity( );
Float max( a, negative_infinity( ) ) = a;
Float max( negative_infinity( ), a ) = a;
Float max( canonical_nan( ), _ ) = canonical_nan( );
Float max( _, canonical_nan( ) ) = canonical_nan( );
Float max( arithmetic_nan( ), _ ) = arithmetic_nan( );
Float max( _, arithmetic_nan( ) ) = arithmetic_nan( );
Float max( fval( a ), fval( b ) ) = fval( max( a, b ) );

Float sqrt( Float f:fval( real v ) ) {
  try {
    return fval( sqrt( v ) );
  } catch ex: {
    return fval( 0.0 );
  }
}
Float sqrt( Float f ) = f;

Float abs( Float f:fval( real v ) ) = fval( abs( v ) );
Float abs( Float f ) = f;

Float ceil( Float f:fval( real v ) ) = fval( toReal( ceil( v ) ) );
Float ceil( Float f ) = f;

Float floor( Float f:fval( real v ) ) = fval( toReal( floor( v ) ) );
Float floor( Float f ) = f;

Float neg( fval( v ) ) = fval( -v );
Float neg( positive_infinity( ) ) = negative_infinity( );
Float neg( negative_infinity( ) ) = positive_infinity( );
Float neg( Float f ) = f;

Float fnearest( fval( v ) ) = fval( fnearest( v ) );
Float fnearest( Float f ) = f;

real fnearest( real f ) {
  int ival = toInt( f );
  real frac = f - ival;
      
  if ( frac < 0.5 ) {
    return toReal( ival );
  } else if ( frac > 0.5 ) {
    return toReal( ival + 1 );
  } else { // if two values are equally near, return the even one
    if ( ival % 2 == 0 ) {
      return toReal( ival );
    } else {
      return toReal( ival + 1 );
    }
  }
}

Float add( fval( a ), fval( b ) ) = fval( a + b );
Float add( positive_infinity( ), fval( _ ) ) = positive_infinity( );
Float add( fval( _ ), positive_infinity( ) ) = positive_infinity( );
Float add( negative_infinity( ), fval( _ ) ) = negative_infinity( );
Float add( fval( _ ), negative_infinity( ) ) = negative_infinity( );
Float add( negative_infinity( ), negative_infinity( ) ) = negative_infinity( );
Float add( positive_infinity( ), positive_infinity( ) ) = positive_infinity( );
Float add( negative_infinity( ), positive_infinity( ) ) = fval( 0.0 );
Float add( positive_infinity( ), negative_infinity( ) ) = fval( 0.0 );

Float subtract( fval( a ), fval( b ) ) = fval( a - b );
Float subtract( positive_infinity( ), fval( _ ) ) = positive_infinity( );
Float subtract( fval( _ ), positive_infinity( ) ) = negative_infinity( );
Float subtract( negative_infinity( ), fval( _ ) ) = negative_infinity( );
Float subtract( fval( _ ), negative_infinity( ) ) = positive_infinity( );
Float subtract( negative_infinity( ), negative_infinity( ) ) = positive_infinity( );
Float subtract( positive_infinity( ), positive_infinity( ) ) = positive_infinity( );
Float subtract( negative_infinity( ), positive_infinity( ) ) = negative_infinity( );
Float subtract( positive_infinity( ), negative_infinity( ) ) = positive_infinity( );

Float multiply( fval( a ), fval( b ) ) = fval( a * b );
Float multiply( positive_infinity( ), positive_infinity( ) ) = positive_infinity( );
Float multiply( negative_infinity( ), negative_infinity( ) ) = positive_infinity( );
Float multiply( negative_infinity( ), positive_infinity( ) ) = negative_infinity( );
Float multiply( positive_infinity( ), negative_infinity( ) ) = negative_infinity( );
Float multiply( positive_infinity( ), fval( 0 ) ) = fval( 0.0 );
Float multiply( positive_infinity( ), fval( a ) ) = ( a > 0 ? positive_infinity( ) : negative_infinity( ) );
Float multiply( fval( 0.0 ), positive_infinity( ) ) = fval( 0 );
Float multiply( fval( a ), positive_infinity( ) ) = ( a > 0 ? positive_infinity( ) : negative_infinity( ) );
Float multiply( negative_infinity( ), fval( 0 ) ) = fval( 0.0 );
Float multiply( negative_infinity( ), fval( a ) ) = ( a < 0 ? positive_infinity( ) : negative_infinity( ) );
Float multiply( fval( 0.0 ), negative_infinity( ) ) = fval( 0.0 );
Float multiply( fval( a ), negative_infinity( ) ) = ( a < 0 ? positive_infinity( ) : negative_infinity( ) );

// Unknown if 0.0 or -0.0. So arbitrary infinity
Float divide( fval( a ), fval( 0.0 ) ) = arbitrary_infinity( );
Float divide( fval( a ), fval( b ) ) = fval( a / b );
Float divide( positive_infinity( ), positive_infinity( ) ) = fval( 0.0 );
Float divide( negative_infinity( ), negative_infinity( ) ) = fval( 0.0 );
Float divide( negative_infinity( ), positive_infinity( ) ) = fval( 0.0 );
Float divide( positive_infinity( ), negative_infinity( ) ) = fval( 0.0 );
Float divide( positive_infinity( ), fval( 0.0 ) ) = arbitrary_infinity( );
Float divide( positive_infinity( ), fval( a ) ) = ( a > 0 ? positive_infinity( ) : negative_infinity( ) );
Float divide( negative_infinity( ), fval( 0.0 ) ) = arbitrary_infinity( );
Float divide( negative_infinity( ), fval( a ) ) = ( a < 0 ? positive_infinity( ) : negative_infinity( ) );
Float divide( fval( a ), positive_infinity( ) ) = fval( 0.0 );
Float divide( fval( a ), negative_infinity( ) ) = fval( 0.0 );
Float divide( fval( a ), arbitrary_infinity( ) ) = fval( 0.0 );

int signif( 32 ) = 23;
int signif( 64 ) = 52;
int expon( 32 ) = 8;
int expon( 64 ) = 11;
int fbias( int N ) = pow2( expon( N ) - 1 ) - 1;

int pow2( int N ) = toInt( pow( 2, N ) );
int pow10( int N ) = toInt( pow( 10, N ) );

Float clean( f:fval( a ), int N ) {
  <sig,expo> = estimateFloatProps( a, N );
    
  if ( overflows( <sig,expo>, N ) ) {
    return a > 0 ? positive_infinity( ) : negative_infinity( );
  } else {
    real v = toReal( sig );
    if ( expo > 0 ) {
      for ( i <- [0..expo] ) {
        v = v * 2.0;
      }
    } else if ( expo < 0 ) {
      for ( i <- [0..-expo] ) {
        v = v * 0.5;
      }
    }
    return fval( v );
  }
}
Float clean( Float f, int N ) = f;

bool overflows( real f, int N ) = overflows( estimateFloatProps( f, N ) );
bool overflows( <int sig,int expo>, int N )
  //= ( abs( sig ) > pow2( signif( N ) ) || expo + fbias( N ) + signif( N ) >= pow2( expon( N ) ) );
  = ( abs( sig ) >= pow2( signif( N ) ) || expo + fbias( N ) + signif( N ) >= pow2( expon( N ) ) );

tuple[int signif,int expon] estimateFloatProps( real f, int N ) {
  bool isPositive = ( f > 0 );
  f = abs( f );
  
  int exp = 0;
  if ( f * 2 < pow2( signif( N ) ) ) {
    while ( f != toInt( f ) && f * 2 < pow2( signif( N ) ) && exp + fbias( N ) + signif( N ) - 1 > 0 ) {
      exp = exp - 1;
      f = f * 2;
    }
    
    f = round( f );
    if ( f == 0 ) {
      exp = 0;
    } else {
      // If it resolved nothing, roll back
      while ( f / 2 == toInt( f / 2 ) && f / 2 > 0 && exp < 0 ) {
        exp = exp + 1;
        f = f / 2;
      }
    }
  } else {
    while ( ( f >= pow2( signif( N ) ) || f / 2 == toInt( f / 2 ) ) && exp + fbias( N ) + signif( N ) + 1 < pow2( expon( N ) ) ) {
      exp = exp + 1;
      f = f / 2;
    }
    f = floor( f );
  }
  int m = ( isPositive ? 1 : -1 ) * toInt( round( f ) );
  return <m,exp>;
}

bool eq( fval( a ), fval( b ) ) = abs( a - b ) < 0.001 || abs( a - b ) / max( abs( a ), abs( b ) ) < 0.001;
bool eq( arbitrary_infinity( ), positive_infinity( ) ) = true;
bool eq( arbitrary_infinity( ), negative_infinity( ) ) = true;
bool eq( positive_infinity( ), arbitrary_infinity( ) ) = true;
bool eq( negative_infinity( ), arbitrary_infinity( ) ) = true;
bool eq( Float a, Float b ) = ( a == b );

bool ge( fval( a ), fval( b ) ) = ( a >= b );
bool ge( positive_infinity( ), _ ) = true;
bool ge( Float _, Float _ ) = false;

bool le( fval( a ), fval( b ) ) = ( a <= b );
bool le( _, positive_infinity( ) ) = true;
bool le( Float _, Float _ ) = false;

bool gt( fval( a ), fval( b ) ) = ( a > b );
bool gt( positive_infinity( ), positive_infinity( ) ) = false;
bool gt( positive_infinity( ), _ ) = true;
bool gt( Float _, Float _ ) = false;

bool lt( fval( a ), fval( b ) ) = ( a < b );
bool lt( positive_infinity( ), positive_infinity( ) ) = false;
bool lt( _, positive_infinity( ) ) = true;
bool lt( Float _, Float _ ) = false;

int trunc_u( fval( real v ), int destN ) = trunc_u( v, destN );
int trunc_u( Float f, int destN ) = 0; // undefined

int trunc_u( real f, int destN ) {
  int i = toInt( f );
  if ( i >= pow2( destN ) ) {
    return 0; // undefined
  } else {
    return i;
  }
}

int trunc_s( fval( real v ), int destN ) = trunc_s( v, destN );
int trunc_s( Float f, int destN ) = 0; // undefined

int trunc_s( real f, int destN ) {
  int i = toInt( f );
  if ( i >= pow2( destN - 1 ) || i < -pow2( destN - 1 ) ) {
    return 0; // undefined
  } else {
    return i;
  }
}