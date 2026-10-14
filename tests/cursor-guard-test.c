#include <assert.h>
#include <stdio.h>
#include <math.h>
#include "cursor_guard.h"
static int checks;
static void expect(CGRect request, CGRect window, CGRect expected) {
 CGRect got=exerunner_guard_cursor_rect(request,window);
 assert(CGRectEqualToRect(got,expected));checks++;
}
int main(void) {
 CGRect laptop=CGRectMake(0,0,1728,1117), monitor=CGRectMake(0,0,1920,1080);
 expect(laptop,laptop,CGRectMake(2,2,1724,1113));
 expect(monitor,monitor,CGRectMake(2,2,1916,1076));
 expect(CGRectInfinite,laptop,CGRectInfinite);expect(CGRectNull,laptop,CGRectNull);
 expect(CGRectZero,laptop,CGRectZero);
 expect(CGRectMake(800,500,1,1),laptop,CGRectMake(800,500,1,1));
 expect(CGRectMake(800,500,4,10),laptop,CGRectMake(800,500,4,10));
 expect(CGRectMake(3000,0,100,100),laptop,CGRectMake(3000,0,100,100));
 expect(CGRectMake(-1728,0,3648,1117),monitor,CGRectMake(2,2,1916,1076));
 expect(CGRectMake(-1920,-100,5000,2000),CGRectMake(-1728,0,1728,1117),CGRectMake(-1726,2,1724,1113));
 expect(CGRectMake(100,100,400,300),CGRectMake(120,150,450,300),CGRectMake(122,152,376,246));
 expect(CGRectMake(100,100,400,300),CGRectZero,CGRectMake(100,100,400,300));
 for(int scale=1;scale<=2;scale++) {
  CGRect pixels=CGRectMake(-1920*scale,0,1920*scale,1080*scale);
  CGRect points=CGRectMake(pixels.origin.x/scale,pixels.origin.y/scale,pixels.size.width/scale,pixels.size.height/scale);
  CGRect safe=exerunner_guard_cursor_rect(points,points);
  assert((safe.origin.x-points.origin.x)*scale==2*scale);
  assert((CGRectGetMaxX(points)-CGRectGetMaxX(safe))*scale==2*scale);
  for(int x=-4;x<=4;x++) for(int y=-4;y<=4;y++) {
   double px=fmax(CGRectGetMinX(safe),fmin(CGRectGetMaxX(safe)-1,CGRectGetMaxX(points)+x));
   double py=fmax(CGRectGetMinY(safe),fmin(CGRectGetMaxY(safe)-1,CGRectGetMaxY(points)+y));
   assert(px>CGRectGetMinX(points)&&px<CGRectGetMaxX(points)-1);
   assert(py>CGRectGetMinY(points)&&py<CGRectGetMaxY(points)-1);checks++;
  }
 }
 printf("%d capture geometry, Retina and corner safety checks passed\n",checks);
}
