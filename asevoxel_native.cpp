// Unified minimal native acceleration (transform_voxel + calculate_face_visibility)

extern "C" {
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
}

#include <cmath>
#include <vector>
#include <algorithm>
#include <unordered_map>
#include <unordered_set>
#include <string>
#include <cstring>  // For strcmp
#include <array>   // <-- Added

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif
static constexpr double PI = 3.14159265358979323846;

static double getNum(lua_State* L, int idx, const char* k, double def=0.0) {
  double r = def;
  lua_getfield(L, idx, k);
  if (lua_isnumber(L, -1)) r = lua_tonumber(L, -1);
  lua_pop(L,1);
  return r;
}

static int getFieldInteger(lua_State* L, int idx, const char* k, int def=0) {
  int r = def;
  lua_getfield(L, idx, k);
  if (lua_isnumber(L, -1)) r = (int)lua_tointeger(L, -1);
  lua_pop(L,1);
  return r;
}

// transform_voxel(voxelTbl, paramsTbl)
static int l_transform_voxel(lua_State* L) {
  if (!lua_istable(L,1) || !lua_istable(L,2)) {
    lua_pushnil(L); lua_pushstring(L,"expected (voxel, params) tables"); return 2;
  }
  double vx = getNum(L,1,"x",0.0);
  double vy = getNum(L,1,"y",0.0);
  double vz = getNum(L,1,"z",0.0);

  double mx=0,my=0,mz=0;
  lua_getfield(L,2,"middlePoint");
  if (lua_istable(L,-1)) {
    mx = getNum(L,-1,"x",0.0);
    my = getNum(L,-1,"y",0.0);
    mz = getNum(L,-1,"z",0.0);
  }
  lua_pop(L,1);

  double xr = getNum(L,2,"xRotation",0.0);
  double yr = getNum(L,2,"yRotation",0.0);
  double zr = getNum(L,2,"zRotation",0.0);

  double x = vx - mx;
  double y = vy - my;
  double z = vz - mz;

  const double RX = xr * PI/180.0;
  const double RY = yr * PI/180.0;
  const double RZ = zr * PI/180.0;
  const double cx = std::cos(RX), sx = std::sin(RX);
  const double cy = std::cos(RY), sy = std::sin(RY);
  const double cz = std::cos(RZ), sz = std::sin(RZ);

  { double y2 = y*cx - z*sx; double z2 = y*sx + z*cx; y = y2; z = z2; }
  { double x2 = x*cy + z*sy; double z3 = -x*sy + z*cy; x = x2; z = z3; }
  { double x3 = x*cz - y*sz; double y3 = x*sz + y*cz; x = x3; y = y3; }

  x += mx; y += my; z += mz;

  lua_createtable(L,0,4);
  lua_pushnumber(L,x); lua_setfield(L,-2,"x");
  lua_pushnumber(L,y); lua_setfield(L,-2,"y");
  lua_pushnumber(L,z); lua_setfield(L,-2,"z");

  // Pass color table through (no deep clone needed for current usage)
  lua_getfield(L,1,"color");
  if (lua_istable(L,-1)) {
    lua_setfield(L,-2,"color");
  } else {
    lua_pop(L,1);
  }
  return 1;
}

// calculate_face_visibility(voxel, cameraPos, orthBool, rotationParams)
static int l_calculate_face_visibility(lua_State* L) {
  if (!lua_istable(L,1) || !lua_istable(L,2) || !lua_istable(L,4)) {
    lua_pushnil(L); lua_pushstring(L,"args: voxel, cameraPos, orthBool, rotationParams"); return 2;
  }
  double vx = getNum(L,1,"x",0.0);
  double vy = getNum(L,1,"y",0.0);
  double vz = getNum(L,1,"z",0.0);
  double cxPos = getNum(L,2,"x",0.0);
  double cyPos = getNum(L,2,"y",0.0);
  double czPos = getNum(L,2,"z",0.0);
  double xr = getNum(L,4,"xRotation",0.0);
  double yr = getNum(L,4,"yRotation",0.0);
  double zr = getNum(L,4,"zRotation",0.0);
  double voxelSize = getNum(L,4,"voxelSize",1.0);
  if (voxelSize < 0.001) voxelSize = 0.001;

  const double RX = xr * PI/180.0;
  const double RY = yr * PI/180.0;
  const double RZ = zr * PI/180.0;
  const double cx = std::cos(RX), sx = std::sin(RX);
  const double cy = std::cos(RY), sy = std::sin(RY);
  const double cz = std::cos(RZ), sz = std::sin(RZ);

  double vcx = std::floor(vx + 0.5);
  double vcy = std::floor(vy + 0.5);
  double vcz = std::floor(vz + 0.5);
  double vxv = cxPos - vcx;
  double vyv = cyPos - vcy;
  double vzv = czPos - vcz;
  double mag = std::sqrt(vxv*vxv + vyv*vyv + vzv*vzv);
  if (mag > 1e-4) { vxv/=mag; vyv/=mag; vzv/=mag; }

  struct Face { const char* name; double nx,ny,nz; };
  static const Face faces[] = {
    {"front",0,0,1},{"back",0,0,-1},{"right",1,0,0},
    {"left",-1,0,0},{"top",0,1,0},{"bottom",0,-1,0}
  };

  lua_createtable(L,0,6);
  double threshold = 0.01 / std::min(3.0, voxelSize);

  for (auto &f : faces) {
    double x1=f.nx, y1=f.ny, z1=f.nz;
    { double y2 = y1*cx - z1*sx; double z2 = y1*sx + z1*cx; y1=y2; z1=z2; }
    { double x2 = x1*cy + z1*sy; double z3 = -x1*sy + z1*cy; x1=x2; z1=z3; }
    { double x3 = x1*cz - y1*sz; double y3 = x1*sz + y1*cz; x1=x3; y1=y3; }
    double dot = x1*vxv + y1*vyv + z1*vzv;
    lua_pushboolean(L, dot > threshold);
    lua_setfield(L,-2,f.name);
  }
  return 1;
}

// --------------------------- BASIC RENDERER (Phase 2+3) -----------------------
// Lua: render_basic(voxels, params)
// See diff description for full parameter/return spec.

namespace {
struct Voxel {
  float x,y,z;
  unsigned char r,g,b,a;
};
struct FacePoly {
  float x[4];
  float y[4];
  float depth;
  unsigned char r,g,b,a;
};

// Basic shading formula (Formula B)
static inline float basicBrightness(float dot,float shadePct,float lightPct){
  if (dot<=0.f) dot=0.f;
  float si = shadePct/100.f;
  float li = lightPct/100.f;
  float minB = 0.05f + 0.9f*li;
  float curve = (1.f - si); curve*=curve;
  float exponent = 1.f + 6.f*curve;
  float powered = (dot>0.f)? std::pow(dot, exponent):0.f;
  float b = minB + (1.f - minB)*powered;
  if (b<0.f) b=0.f; else if (b>1.f) b=1.f;
  return b;
}

static void rasterQuad(const FacePoly& poly,int W,int H,std::vector<unsigned char>& buf){
  float minY=poly.y[0], maxY=poly.y[0];
  for(int i=1;i<4;i++){ if(poly.y[i]<minY)minY=poly.y[i]; if(poly.y[i]>maxY)maxY=poly.y[i]; }
  int y0=(int)std::floor(minY);
  int y1=(int)std::ceil (maxY);
  if (y0<0) y0=0;
  if (y1>H) y1=H;
  struct Edge{float x0,y0,x1,y1;};
  Edge edges[4];
  for(int i=0;i<4;i++){
    int j=(i+1)&3;
    float x0=poly.x[i], y0p=poly.y[i];
    float x1=poly.x[j], y1p=poly.y[j];
    if (y0p<y1p) edges[i]={x0,y0p,x1,y1p};
    else edges[i]={x1,y1p,x0,y0p};
  }
  for(int y=y0;y<y1;y++){
    float scan = y+0.5f;
    std::vector<float> xs;
    for(int e=0;e<4;e++){
      auto &E=edges[e];
      if (scan>=E.y0 && scan<E.y1){
        float t=(scan-E.y0)/(E.y1-E.y0);
        xs.push_back(E.x0 + (E.x1-E.x0)*t);
      }
    }
    if (xs.size() < 2) continue;
    std::sort(xs.begin(), xs.end());
    for(size_t k=0; k + 1 < xs.size(); k += 2){
      float xa = xs[k], xb = xs[k+1];
      if (xa>xb) std::swap(xa,xb);
      int ix0=(int)std::floor(xa+0.5f);
      int ix1=(int)std::floor(xb-0.5f);
      if (ix0<0) ix0=0;
      if (ix1>=W) ix1=W-1;
      for(int x=ix0;x<=ix1;x++){
        size_t off=((size_t)y*W + x)*4;
        buf[off+0]=poly.r; buf[off+1]=poly.g; buf[off+2]=poly.b; buf[off+3]=poly.a;
      }
    }
  }
}

static inline bool faceVisible(float nx,float ny,float nz,
                               float vx,float vy,float vz,
                               float threshold){
  return (nx*vx + ny*vy + nz*vz) > threshold;
}
static inline void rotateNormal(float &x,float &y,float &z,
                                float cx,float sx,float cy,float sy,float cz,float sz){
  float y2=y*cx - z*sx; float z2=y*sx + z*cx; y=y2; z=z2;
  float x2=x*cy + z*sy; float z3=-x*sy + z*cy; x=x2; z=z3;
  float x3=x*cz - y*sz; float y3=x*sz + y*cz; x=x3; y=y3;
}

static const int FACE_IDX[6][4]={
  {5,6,7,8},{2,1,4,3},{6,2,3,7},{1,5,8,4},{8,7,3,4},{1,2,6,5}
};
static const float LOCAL_FACE_NORMALS[6][3]={
  {0,0,1},{0,0,-1},{1,0,0},{-1,0,0},{0,1,0},{0,-1,0}
};
static const float UNIT_VERTS[8][3]={
  {-0.5f,-0.5f,-0.5f},{ 0.5f,-0.5f,-0.5f},{ 0.5f, 0.5f,-0.5f},{-0.5f, 0.5f,-0.5f},
  {-0.5f,-0.5f, 0.5f},{ 0.5f,-0.5f, 0.5f},{ 0.5f, 0.5f, 0.5f},{-0.5f, 0.5f, 0.5f}
};

struct OrthoCacheKey{int xr,yr,zr; float size; bool operator==(const OrthoCacheKey&o)const{
  return xr==o.xr && yr==o.yr && zr==o.zr && size==o.size;
}};
struct OrthoCacheKeyHash{
  std::size_t operator()(OrthoCacheKey const& k) const noexcept{
    std::size_t h=1469598103934665603ull;
    auto mix=[&](std::size_t v){ h^=v; h*=1099511628211ull; };
    mix(std::hash<int>()(k.xr));
    mix(std::hash<int>()(k.yr));
    mix(std::hash<int>()(k.zr));
    mix(std::hash<int>()((int)(k.size*1000.f)));
    return h;
  }
};
struct RotatedFaceTemplate{
  float vx[6][4];
  float vy[6][4];
  float fnx[6],fny[6],fnz[6];
};
static std::unordered_map<OrthoCacheKey,RotatedFaceTemplate,OrthoCacheKeyHash> g_orthoCache;

static const RotatedFaceTemplate& getOrthoTemplate(int xr,int yr,int zr,float size){
  OrthoCacheKey key{((xr%360)+360)%360,((yr%360)+360)%360,((zr%360)+360)%360,size};
  auto it=g_orthoCache.find(key);
  if(it!=g_orthoCache.end()) return it->second;
  double RX=key.xr*PI/180.0;
  double RY=key.yr*PI/180.0;
  double RZ=key.zr*PI/180.0;
  float cx=(float)std::cos(RX), sx=(float)std::sin(RX);
  float cy=(float)std::cos(RY), sy=(float)std::sin(RY);
  float cz=(float)std::cos(RZ), sz=(float)std::sin(RZ);
  RotatedFaceTemplate tmpl{};
  for(int f=0;f<6;f++){
    float nx=LOCAL_FACE_NORMALS[f][0];
    float ny=LOCAL_FACE_NORMALS[f][1];
    float nz=LOCAL_FACE_NORMALS[f][2];
    rotateNormal(nx,ny,nz,cx,sx,cy,sy,cz,sz);
    tmpl.fnx[f]=nx; tmpl.fny[f]=ny; tmpl.fnz[f]=nz;
  }
  float rvx[8], rvy[8]; // removed unused rvz
  for(int v=0;v<8;v++){
    float x=UNIT_VERTS[v][0]*size;
    float y=UNIT_VERTS[v][1]*size;
    float z=UNIT_VERTS[v][2]*size;
    rotateNormal(x,y,z,cx,sx,cy,sy,cz,sz);
    rvx[v]=x; rvy[v]=y; // rvz was unused, remove assignment
  }
  for(int f=0;f<6;f++){
    for(int i=0;i<4;i++){
      int idx=FACE_IDX[f][i]-1;
      tmpl.vx[f][i]=rvx[idx];
      tmpl.vy[f][i]=rvy[idx];
    }
  }
  return g_orthoCache.emplace(key,tmpl).first->second;
}

static int l_render_basic(lua_State* L){
  if(!lua_istable(L,1)||!lua_istable(L,2)){
    lua_pushnil(L); lua_pushstring(L,"expected (voxels, params)"); return 2;
  }
  int width  =(int)getNum(L,2,"width",200);
  int height =(int)getNum(L,2,"height",200);

  // Accept both "scale" and legacy "scaleLevel"
  float scale=(float)getNum(L,2,"scale",-12345.0);
  if (scale < 0) {
    scale = (float)getNum(L,2,"scaleLevel",1.0);
  }
  if (scale <= 0.f) scale = 1.f;

  // Mesh-mode flag (flat, unshaded; interior faces culled)
  bool meshMode = false;
  lua_getfield(L,2,"mesh");
  if (lua_isboolean(L,-1)) meshMode = lua_toboolean(L,-1)!=0;
  lua_pop(L,1);
  if (!meshMode) {
    lua_getfield(L,2,"meshMode");
    if (lua_isboolean(L,-1)) meshMode = lua_toboolean(L,-1)!=0;
    lua_pop(L,1);
  }

  float xRotDeg=(float)getNum(L,2,"xRotation",0.0);
  float yRotDeg=(float)getNum(L,2,"yRotation",0.0);
  float zRotDeg=(float)getNum(L,2,"zRotation",0.0);
  float shadeIntensity=(float)getNum(L,2,"basicShadeIntensity",50.0);
  float lightIntensity=(float)getNum(L,2,"basicLightIntensity",50.0);
  float fovDeg=(float)getNum(L,2,"fovDegrees",0.0);
  lua_getfield(L,2,"orthogonal");
  bool orthogonal = lua_toboolean(L,-1)!=0; lua_pop(L,1);
  // perspectiveScaleRef ("middle" | "front" | "back")
  std::string perspRef = "middle";
  lua_getfield(L,2,"perspectiveScaleRef");
  if (lua_isstring(L,-1)) {
    const char* pr = lua_tostring(L,-1);
    if (pr && *pr) perspRef = pr;
  }
  lua_pop(L,1);
  // backgroundColor
  unsigned char bgR=0,bgG=0,bgB=0,bgA=0;
  lua_getfield(L,2,"backgroundColor");
  if(lua_istable(L,-1)){
    bgR=(unsigned char)getFieldInteger(L,-1,"r",0);
    bgG=(unsigned char)getFieldInteger(L,-1,"g",0);
    bgB=(unsigned char)getFieldInteger(L,-1,"b",0);
    bgA=(unsigned char)getFieldInteger(L,-1,"a",0);
  }
  lua_pop(L,1);

  size_t count=lua_rawlen(L,1);
  lua_createtable(L,0,3);
  if(count==0){
    lua_pushinteger(L,width); lua_setfield(L,-2,"width");
    lua_pushinteger(L,height); lua_setfield(L,-2,"height");
    lua_pushlstring(L,"",0); lua_setfield(L,-2,"pixels");
    return 1;
  }
  std::vector<Voxel> voxels;
  voxels.reserve(count);
  float minX=1e9f,minY=1e9f,minZ=1e9f;
  float maxX=-1e9f,maxY=-1e9f,maxZ=-1e9f;
  for(size_t i=1;i<=count;i++){
    lua_rawgeti(L,1,(int)i);
    if(lua_istable(L,-1)){
      int tblIdx = lua_gettop(L);
      Voxel v{0,0,0,255,255,255,255};
      // detect numeric form
      lua_rawgeti(L,tblIdx,1);
      bool numeric = lua_isnumber(L,-1)!=0;
      lua_pop(L,1);
      if(numeric){
        lua_rawgeti(L,tblIdx,1); v.x=(float)lua_tonumber(L,-1); lua_pop(L,1);
        lua_rawgeti(L,tblIdx,2); v.y=(float)lua_tonumber(L,-1); lua_pop(L,1);
        lua_rawgeti(L,tblIdx,3); v.z=(float)lua_tonumber(L,-1); lua_pop(L,1);
        lua_rawgeti(L,tblIdx,4); v.r=(unsigned char)lua_tointeger(L,-1); lua_pop(L,1);
        lua_rawgeti(L,tblIdx,5); v.g=(unsigned char)lua_tointeger(L,-1); lua_pop(L,1);
        lua_rawgeti(L,tblIdx,6); v.b=(unsigned char)lua_tointeger(L,-1); lua_pop(L,1);
        lua_rawgeti(L,tblIdx,7); v.a=(unsigned char)lua_tointeger(L,-1); lua_pop(L,1);
      } else {
        v.x=(float)getNum(L,tblIdx,"x",0);
        v.y=(float)getNum(L,tblIdx,"y",0);
        v.z=(float)getNum(L,tblIdx,"z",0);
        lua_getfield(L,tblIdx,"color");
        if(lua_istable(L,-1)){
          v.r=(unsigned char)getFieldInteger(L,-1,"r",255);
          v.g=(unsigned char)getFieldInteger(L,-1,"g",255);
          v.b=(unsigned char)getFieldInteger(L,-1,"b",255);
          v.a=(unsigned char)getFieldInteger(L,-1,"a",255);
        }
        lua_pop(L,1);
      }
      if(v.x<minX)minX=v.x; if(v.x>maxX)maxX=v.x;
      if(v.y<minY)minY=v.y; if(v.y>maxY)maxY=v.y;
      if(v.z<minZ)minZ=v.z; if(v.z>maxZ)maxZ=v.z;
      voxels.push_back(v);
    }
    lua_pop(L,1);
  }

  // Build occupancy map for mesh mode (string key "x,y,z")
  std::unordered_set<std::string> occ;
  if (meshMode) {
    occ.reserve(voxels.size()*2);
    for (auto &v : voxels) {
      int ix = (int)std::lround(v.x);
      int iy = (int)std::lround(v.y);
      int iz = (int)std::lround(v.z);
      occ.emplace(std::to_string(ix)+","+std::to_string(iy)+","+std::to_string(iz));
    }
  }

  float midX=0.5f*(minX+maxX);
  float midY=0.5f*(minY+maxY);
  float midZ=0.5f*(minZ+maxZ);
  float sizeX=maxX-minX+1.f;
  float sizeY=maxY-minY+1.f;
  float sizeZ=maxZ-minZ+1.f;
  float maxDim=std::max(sizeX,std::max(sizeY,sizeZ));

  float RX=xRotDeg*(float)PI/180.f;
  float RY=yRotDeg*(float)PI/180.f;
  float RZ=zRotDeg*(float)PI/180.f;
  float cx=std::cos(RX), sx=std::sin(RX);
  float cy=std::cos(RY), sy=std::sin(RY);
  float cz=std::cos(RZ), sz=std::sin(RZ);

  // ----------------------------------------------------------------------------
  // PERSPECTIVE & ORTHOGRAPHIC CAMERA (MATCH previewRenderer.lua)
  //   - Stronger FOV warping: camera distance shrinks non‑linearly as FOV increases
  //   - Reference depth scaling: chosen perspectiveScaleRef ("front","middle","back")
  //     stays closest to the user scale while allowing other depths to warp.
  //   - Orthographic path simplified (no template voxelSize distortion).
  // ----------------------------------------------------------------------------
  bool perspective = (!orthogonal && fovDeg > 0.f);
  float focalLength = 0.f;
  float camDist;
  if (perspective) {
    // Clamp FOV and compute warp curve -> amplified factor
    fovDeg = std::max(5.f, std::min(75.f, fovDeg));
    float warpT = (fovDeg - 5.f) / (75.f - 5.f);
    if (warpT < 0.f) warpT = 0.f; if (warpT > 1.f) warpT = 1.f;
    float amplified = std::pow(warpT, 1.f/3.f);
    const float BASE_NEAR = 1.2f;
    const float FAR_EXTRA = 45.f;
    camDist = maxDim * (BASE_NEAR + (1.f - amplified)*(1.f - amplified) * FAR_EXTRA);
    float fovRad = fovDeg * (float)PI / 180.f;
    focalLength = (height / 2.f) / std::tan(fovRad / 2.f);
  } else {
    camDist = maxDim * 5.f;
  }

  // Compute voxelSize
  float voxelSize = scale;
  {
    float maxAllowedPixels = std::min(width, height) * 0.9f;
    if (perspective && focalLength > 1e-6f && maxDim > 0.f) {
      // Rotate AABB corners to derive front/back depths (match basic renderer)
      float RX = xRotDeg*(float)PI/180.f;
      float RY = yRotDeg*(float)PI/180.f;
      float RZ = zRotDeg*(float)PI/180.f;
      float rcx=std::cos(RX), rsx=std::sin(RX);
      float rcy=std::cos(RY), rsy=std::sin(RY);
      float rcz=std::cos(RZ), rsz=std::sin(RZ);
      float zMinRot =  1e9f;
      float zMaxRot = -1e9f;
      for (int ix=0; ix<2; ++ix){
        float cxv = (ix==0)?minX:maxX;
        for (int iy=0; iy<2; ++iy){
          float cyv = (iy==0)?minY:maxY;
          for (int iz=0; iz<2; ++iz){
            float czv = (iz==0)?minZ:maxZ;
            float X = cxv - midX;
            float Y = cyv - midY;
            float Z = czv - midZ;
            { float Y2=Y*rcx - Z*rsx; float Z2=Y*rsx + Z*rcx; Y=Y2; Z=Z2; }
            { float X2=X*rcy + Z*rsy; float Z3=-X*rsy + Z*rcy; X=X2; Z=Z3; }
            { float X3=X*rcz - Y*rsz; float Y3=X*rsz + Y*rcz; X=X3; Y=Y3; }
            float worldZ = Z + midZ;
            if (worldZ < zMinRot) zMinRot = worldZ;
            if (worldZ > zMaxRot) zMaxRot = worldZ;
          }
        }
      }
      float cameraZ = midZ + camDist;
      float depthBack  = std::max(0.001f, cameraZ - zMinRot); // farthest
      float depthFront = std::max(0.001f, cameraZ - zMaxRot); // nearest
      float depthMiddle= std::max(0.001f, camDist);        // model center
      float depthRef = depthMiddle;
      if (perspRef == "front" || perspRef == "Front") depthRef = depthFront;
      else if (perspRef == "back" || perspRef == "Back") depthRef = depthBack;
      voxelSize = scale * (depthRef / focalLength);
      if (voxelSize * maxDim > maxAllowedPixels) voxelSize = maxAllowedPixels / maxDim;
      if (voxelSize <= 0.f) voxelSize = 1.f;
    } else {
      if (voxelSize < 1.f) voxelSize = 1.f;
      if (voxelSize * maxDim > maxAllowedPixels && maxDim > 0.f)
        voxelSize *= (maxAllowedPixels / (voxelSize * maxDim));
    }
  }
  
  // Orthographic template only if voxelSize not degenerate (avoid artifacts)
  // FIX (Basic Ortho Speckle):
  // Previously we used a cached orthographic template (tmpl) that:
  //   1. Quantized angles to whole degrees.
  //   2. Dropped per-vertex rotated Z (depth) variation.
  //   3. Gave every visible face in a voxel identical avgDepth.
  // Result: large numbers of ties in painter's sort => unstable overdraw
  // producing single‑pixel "speckles".
  //
  // To restore correctness we disable the template optimization here and
  // always execute the per‑voxel vertex rotation path (tmpl = nullptr).
  const RotatedFaceTemplate* tmpl = nullptr; // forced off for correctness

  std::vector<FacePoly> polys;
  polys.reserve(voxels.size()*6);

  float threshold = 0.01f / std::min(3.0f, voxelSize);

  // Neighbor offsets to cull interior faces (mesh mode)
  struct NOff { int dx,dy,dz; };
  static const NOff neigh[6] = {
    {0,0, 1},  // front
    {0,0,-1},  // back
    {1,0, 0},  // right
    {-1,0,0},  // left
    {0,1, 0},  // top
    {0,-1,0}   // bottom
  };

  // --------------------------------------------------------------------------
  // UNIFORM VIEW VECTOR FOR BASIC SHADING (anti-speckle fix)
  // --------------------------------------------------------------------------
  // Problem:
  //   When using interactive (relative / absolute) rotation the same Euler
  //   orientation can be reached through incremental matrix multiplications.
  //   Because the previous implementation used a PER-VOXEL view vector
  //   (camera -> voxel center) both face visibility and brightness varied
  //   slightly across a large, nominally flat face (e.g. the top plane).
  //   Small numeric differences around the visibility threshold + painter
  //   ordering produced isolated darker / lighter "dot" artifacts.
  //
  // Solution:
  //   For BASIC shading we want a stylized *uniform* face brightness.
  //   We keep per-voxel view vector ONLY for face visibility in perspective
  //   (so extreme parallax still culls correctly), but we compute a single
  //   global normalized camera direction (camera -> model center) and use
  //   that for:
  //     1. Face visibility threshold test (optional toggle – enabled here)
  //     2. Brightness calculation (always)
  //
  //   This removes sub‑voxel variation and stabilizes ordering across
  //   different rotation interaction paths.
  //
  //   If in the future nuanced per‑voxel falloff is desired for BASIC mode,
  //   guard it behind a param switch (not needed now).
  // --------------------------------------------------------------------------
  float gvx = 0.f, gvy = 0.f, gvz = 1.f; // default (orthographic or fallback)
  if (perspective) {
    gvx = camDist != 0.f ? (midX - midX) : 0.f; // 0
    gvy = camDist != 0.f ? (midY - midY) : 0.f; // 0
    gvz = (midZ + camDist) - midZ;              // camDist
    float gmag = std::sqrt(gvx*gvx + gvy*gvy + gvz*gvz);
    if (gmag > 1e-6f) { gvx /= gmag; gvy /= gmag; gvz /= gmag; }
  }

  for(auto &v: voxels){
    float x=v.x-midX, y=v.y-midY, z=v.z-midZ;
    // rotate center
    { float y2=y*cx - z*sx; float z2=y*sx + z*cx; y=y2; z=z2; }
    { float x2=x*cy + z*sy; double z3=-x*sy + z*cy; x=x2; z=(float)z3; }
    { float x3=x*cz - y*sz; float y3=x*sz + y*cz; x=x3; y=y3; }
    float worldX = x+midX;
    float worldY = y+midY;
    float worldZ = z+midZ;

    float camX=midX, camY=midY, camZ=midZ+camDist;
    // Per‑voxel view vector retained only for perspective culling logic
    float vxv=gvx, vyv=gvy, vzv=gvz;
    if (perspective) {
      // Use per-voxel vector for face visibility (wider FOV correctness),
      // but brightness will use the global (gvx,gvy,gvz) vector.
      float pvx = camX - worldX;
      float pvy = camY - worldY;
      float pvz = camZ - worldZ;
      float pmag = std::sqrt(pvx*pvx + pvy*pvy + pvz*pvz);
      if (pmag > 1e-5f) { pvx/=pmag; pvy/=pmag; pvz/=pmag; }
      vxv = pvx; vyv = pvy; vzv = pvz;
    }

    float screenCX=width*0.5f;
    float screenCY=height*0.5f;

    for(int f=0;f<6;f++){
      // Mesh mode: interior face culling via neighbor occupancy
      if (meshMode) {
        // faces order: 0=front,1=back,2=right,3=left,4=top,5=bottom
        int ix = (int)std::lround(v.x);
        int iy = (int)std::lround(v.y);
        int iz = (int)std::lround(v.z);
        int nx = ix + neigh[f].dx;
        int ny = iy + neigh[f].dy;
        int nz = iz + neigh[f].dz;
        std::string key = std::to_string(nx)+","+std::to_string(ny)+","+std::to_string(nz);
        if (occ.find(key) != occ.end()) {
          continue; // interior, skip
        }
      }

      float nx,ny,nz;
      if(tmpl){
        nx=tmpl->fnx[f]; ny=tmpl->fny[f]; nz=tmpl->fnz[f];
      }else{
        nx=LOCAL_FACE_NORMALS[f][0];
        ny=LOCAL_FACE_NORMALS[f][1];
        nz=LOCAL_FACE_NORMALS[f][2];
        rotateNormal(nx,ny,nz,cx,sx,cy,sy,cz,sz);
      }
      // For consistency, evaluate visibility against *global* view dir in basic mode
      // so borderline faces don't flicker between interaction paths.
      float visDot = nx*gvx + ny*gvy + nz*gvz;
      if (visDot <= threshold) continue;

      // Brightness uses global view vector (gvx/gvy/gvz) for uniformity
      float bright = 1.0f;
      if (!meshMode) {
        float dot = visDot;
        bright = basicBrightness(dot,shadeIntensity,lightIntensity);
      }

      FacePoly poly{};
      poly.r=(unsigned char)std::round(std::min(255.f,v.r*bright));
      poly.g=(unsigned char)std::round(std::min(255.f,v.g*bright));
      poly.b=(unsigned char)std::round(std::min(255.f,v.b*bright));
      poly.a=v.a;
      float avgDepth=0.f;
      // Unified per-vertex path (perspective OR orthographic) to preserve
      // subtle per-vertex depth differences and deterministic order.
      {
        bool usePerspective = perspective;
        for(int i=0;i<4;i++){
          int vidx = FACE_IDX[f][i]-1;
          float lx = UNIT_VERTS[vidx][0]*voxelSize;
          float ly = UNIT_VERTS[vidx][1]*voxelSize;
          float lz = UNIT_VERTS[vidx][2]*voxelSize;
          rotateNormal(lx,ly,lz,cx,sx,cy,sy,cz,sz);
          float wx = worldX*voxelSize + lx;
          float wy = worldY*voxelSize + ly;
          float wzLocal = worldZ + (lz/voxelSize);

          float depth;
          float s = 1.0f;
          if(usePerspective){
            depth = (camZ - wzLocal);
            if(depth < 0.001f) depth = 0.001f;
            s = (focalLength > 0.0f) ? (focalLength / depth) : 1.0f;
          } else {
            // Orthographic: retain subtle per-vertex depth; add tiny bias along normal
            depth = (camZ - wzLocal) + nz * 0.001f;
          }

          poly.x[i] = screenCX + (wx - midX*voxelSize)*s;
          poly.y[i] = screenCY + (wy - midY*voxelSize)*s;
          avgDepth += depth;
        }
        avgDepth /= 4.f;
      }
      poly.depth=avgDepth;
      polys.push_back(poly);
    }
  }

  std::sort(polys.begin(),polys.end(),[](const FacePoly&a,const FacePoly&b){
    return a.depth > b.depth; // far to near
  });

  std::vector<unsigned char> buffer((size_t)width*height*4,0);
  for(int y=0;y<height;y++){
    for(int x=0;x<width;x++){
      size_t off=((size_t)y*width + x)*4;
      buffer[off+0]=bgR; buffer[off+1]=bgG; buffer[off+2]=bgB; buffer[off+3]=bgA;
    }
  }
  for(auto &p: polys) rasterQuad(p,width,height,buffer);

  lua_pushinteger(L,width); lua_setfield(L,-2,"width");
  lua_pushinteger(L,height); lua_setfield(L,-2,"height");
  lua_pushlstring(L,(const char*)buffer.data(), buffer.size());
  lua_setfield(L,-2,"pixels");
  return 1;
}

// ======================== NATIVE SHADER SYSTEM ========================
// Shader data structures and implementations

struct ShaderFace {
  float voxelX, voxelY, voxelZ;
  std::string faceName;
  float normalX, normalY, normalZ;
  unsigned char r, g, b, a;
};

struct ShaderData {
  std::vector<ShaderFace> faces;
  float cameraX, cameraY, cameraZ;
  float cameraDirX, cameraDirY, cameraDirZ;
  float middleX, middleY, middleZ;
  int width, height;
  float voxelSize;
};

struct ShaderParams {
  std::unordered_map<std::string, double> numbers;
  std::unordered_map<std::string, std::string> strings;
  std::unordered_map<std::string, bool> bools;
  std::unordered_map<std::string, std::array<unsigned char, 4>> colors;
};

// Helper: normalize vector
static inline void normalizeVec(float& x, float& y, float& z) {
  float len = std::sqrt(x*x + y*y + z*z);
  if (len > 1e-6f) { x /= len; y /= len; z /= len; }
}

// Helper: dot product
static inline float dotVec(float x1, float y1, float z1, float x2, float y2, float z2) {
  return x1*x2 + y1*y2 + z1*z2;
}

// Helper: check if color is pure
static inline bool isPureColor(unsigned char r, unsigned char g, unsigned char b) {
  const int threshold = 10;
  bool pureR = (r >= 245) && (g <= threshold) && (b <= threshold);
  bool pureG = (g >= 245) && (r <= threshold) && (b <= threshold);
  bool pureB = (b >= 245) && (r <= threshold) && (g <= threshold);
  bool pureC = (g >= 245) && (b >= 245) && (r <= threshold);
  bool pureM = (r >= 245) && (b >= 245) && (g <= threshold);
  bool pureY = (r >= 245) && (g >= 245) && (b <= threshold);
  bool pureK = (r <= threshold) && (g <= threshold) && (b <= threshold);
  bool pureW = (r >= 245) && (g >= 245) && (b >= 245);
  return pureR || pureG || pureB || pureC || pureM || pureY || pureK || pureW;
}

// SHADER: Basic Lighting
static void shader_basic(ShaderData& data, const ShaderParams& params) {
  float lightIntensity = params.numbers.count("lightIntensity") ? 
    (float)params.numbers.at("lightIntensity") : 50.0f;
  float shadeIntensity = params.numbers.count("shadeIntensity") ? 
    (float)params.numbers.at("shadeIntensity") : 50.0f;
  
  float camDirX = data.cameraDirX;
  float camDirY = data.cameraDirY;
  float camDirZ = data.cameraDirZ;
  normalizeVec(camDirX, camDirY, camDirZ);
  
  for (auto& face : data.faces) {
    float normalDot = dotVec(face.normalX, face.normalY, face.normalZ, camDirX, camDirY, camDirZ);
    float t = (normalDot + 1.0f) / 2.0f;
    float brightness = shadeIntensity + (lightIntensity - shadeIntensity) * t;
    float factor = brightness / 100.0f;
    
    face.r = (unsigned char)std::min(255, (int)(face.r * factor + 0.5f));
    face.g = (unsigned char)std::min(255, (int)(face.g * factor + 0.5f));
    face.b = (unsigned char)std::min(255, (int)(face.b * factor + 0.5f));
  }
}

// SHADER: Dynamic Lighting
static void shader_dynamic(ShaderData& data, const ShaderParams& params) {
  float pitch = params.numbers.count("pitch") ? (float)params.numbers.at("pitch") : 25.0f;
  float yaw = params.numbers.count("yaw") ? (float)params.numbers.at("yaw") : 25.0f;
  float diffuseIntensity = params.numbers.count("diffuse") ? 
    (float)params.numbers.at("diffuse") / 100.0f : 0.6f;
  float ambientIntensity = params.numbers.count("ambient") ? 
    (float)params.numbers.at("ambient") / 100.0f : 0.3f;
  float diameter = params.numbers.count("diameter") ? (float)params.numbers.at("diameter") : 100.0f;
  bool rimEnabled = params.bools.count("rimEnabled") && params.bools.at("rimEnabled");
  
  auto lightCol = params.colors.count("lightColor") ? 
    params.colors.at("lightColor") : std::array<unsigned char,4>{255,255,255,255};
  float lr = lightCol[0] / 255.0f;
  float lg = lightCol[1] / 255.0f;
  float lb = lightCol[2] / 255.0f;
  
  float yawRad = yaw * (float)PI / 180.0f;
  float pitchRad = pitch * (float)PI / 180.0f;
  float Lx = std::cos(yawRad) * std::cos(pitchRad);
  float Ly = std::sin(pitchRad);
  float Lz = std::sin(yawRad) * std::cos(pitchRad);
  normalizeVec(Lx, Ly, Lz);
  
  float exponent = 1.0f + (1.0f - diffuseIntensity) * 3.0f;
  
  float viewDirX = data.cameraDirX;
  float viewDirY = data.cameraDirY;
  float viewDirZ = data.cameraDirZ;
  normalizeVec(viewDirX, viewDirY, viewDirZ);
  
  for (auto& face : data.faces) {
    float ndotl = dotVec(face.normalX, face.normalY, face.normalZ, Lx, Ly, Lz);
    if (ndotl < 0) ndotl = 0;
    
    float diffuse = std::pow(ndotl, exponent);
    
    if (diameter > 0) {
      float toVoxelX = face.voxelX - data.middleX;
      float toVoxelY = face.voxelY - data.middleY;
      float toVoxelZ = face.voxelZ - data.middleZ;
      
      float alongAxis = dotVec(toVoxelX, toVoxelY, toVoxelZ, Lx, Ly, Lz);
      float perpX = toVoxelX - alongAxis * Lx;
      float perpY = toVoxelY - alongAxis * Ly;
      float perpZ = toVoxelZ - alongAxis * Lz;
      float perpDist = std::sqrt(perpX*perpX + perpY*perpY + perpZ*perpZ);
      
      float radius = diameter / 2.0f;
      if (radius > 0) {
        float radialFactor = 1.0f - (perpDist / radius);
        if (radialFactor < 0) radialFactor = 0;
        diffuse *= radialFactor;
      }
    }
    
    diffuse *= diffuseIntensity;
    
    float baseR = face.r;
    float baseG = face.g;
    float baseB = face.b;
    
    float r = baseR * (ambientIntensity + diffuse * lr);
    float g = baseG * (ambientIntensity + diffuse * lg);
    float b = baseB * (ambientIntensity + diffuse * lb);
    
    if (rimEnabled) {
      float ndotv = dotVec(face.normalX, face.normalY, face.normalZ, viewDirX, viewDirY, viewDirZ);
      if (ndotv > 0) {
        float edge = 1.0f - ndotv;
        float rimStart = 0.55f, rimEnd = 0.95f;
        if (edge > rimStart) {
          float t = (edge - rimStart) / (rimEnd - rimStart);
          if (t > 1.0f) t = 1.0f;
          t = t * t * (3.0f - 2.0f * t);
          float rim = 0.6f * t;
          r += lr * rim * 255.0f;
          g += lg * rim * 255.0f;
          b += lb * rim * 255.0f;
        }
      }
    }
    
    face.r = (unsigned char)std::min(255, std::max(0, (int)(r + 0.5f)));
    face.g = (unsigned char)std::min(255, std::max(0, (int)(g + 0.5f)));
    face.b = (unsigned char)std::min(255, std::max(0, (int)(b + 0.5f)));
  }
}

// SHADER: FaceShade
static void shader_faceshade(ShaderData& data, const ShaderParams& params) {
  std::string shadingMode = params.strings.count("shadingMode") ? 
    params.strings.at("shadingMode") : "alpha";
  bool materialMode = params.bools.count("materialMode") && params.bools.at("materialMode");
  bool enableTint = params.bools.count("enableTint") && params.bools.at("enableTint");
  
  std::unordered_map<std::string, std::array<unsigned char,4>> faceColors;
  faceColors["top"] = params.colors.count("topColor") ? 
    params.colors.at("topColor") : std::array<unsigned char,4>{255,255,255,255};
  faceColors["bottom"] = params.colors.count("bottomColor") ? 
    params.colors.at("bottomColor") : std::array<unsigned char,4>{255,255,255,255};
  faceColors["front"] = params.colors.count("frontColor") ? 
    params.colors.at("frontColor") : std::array<unsigned char,4>{255,255,255,255};
  faceColors["back"] = params.colors.count("backColor") ? 
    params.colors.at("backColor") : std::array<unsigned char,4>{255,255,255,255};
  faceColors["left"] = params.colors.count("leftColor") ? 
    params.colors.at("leftColor") : std::array<unsigned char,4>{255,255,255,255};
  faceColors["right"] = params.colors.count("rightColor") ? 
    params.colors.at("rightColor") : std::array<unsigned char,4>{255,255,255,255};
  
  for (auto& face : data.faces) {
    if (materialMode && isPureColor(face.r, face.g, face.b)) continue;
    
    auto it = faceColors.find(face.faceName);
    if (it == faceColors.end()) continue;
    
    auto& faceColor = it->second;
    
    if (shadingMode == "alpha") {
      float brightness = faceColor[3] / 255.0f;
      if (enableTint) {
        float tintR = faceColor[0] / 255.0f;
        float tintG = faceColor[1] / 255.0f;
        float tintB = faceColor[2] / 255.0f;
        face.r = (unsigned char)(face.r * brightness * tintR + 0.5f);
        face.g = (unsigned char)(face.g * brightness * tintG + 0.5f);
        face.b = (unsigned char)(face.b * brightness * tintB + 0.5f);
      } else {
        face.r = (unsigned char)(face.r * brightness + 0.5f);
        face.g = (unsigned char)(face.g * brightness + 0.5f);
        face.b = (unsigned char)(face.b * brightness + 0.5f);
      }
    } else {
      face.r = faceColor[0];
      face.g = faceColor[1];
      face.b = faceColor[2];
    }
  }
}

// SHADER: Iso
static void shader_iso(ShaderData& data, const ShaderParams& params) {
  std::string shadingMode = params.strings.count("shadingMode") ? 
    params.strings.at("shadingMode") : "alpha";
  bool materialMode = params.bools.count("materialMode") && params.bools.at("materialMode");
  bool enableTint = params.bools.count("enableTint") && params.bools.at("enableTint");
  
  auto topColor = params.colors.count("topColor") ? 
    params.colors.at("topColor") : std::array<unsigned char,4>{255,255,255,255};
  auto leftColor = params.colors.count("leftColor") ? 
    params.colors.at("leftColor") : std::array<unsigned char,4>{235,235,235,230};
  auto rightColor = params.colors.count("rightColor") ? 
    params.colors.at("rightColor") : std::array<unsigned char,4>{210,210,210,210};
  
  struct FaceInfo { std::string name; float dot; float nx; };
  std::unordered_map<std::string, FaceInfo> faceMap;
  
  for (auto& face : data.faces) {
    faceMap[face.faceName] = {face.faceName, face.normalZ, face.normalX};
  }
  
  float dTop = faceMap.count("top") ? faceMap["top"].dot : -1e9f;
  float dBottom = faceMap.count("bottom") ? faceMap["bottom"].dot : -1e9f;
  std::string isoTop = (dTop >= dBottom) ? "top" : "bottom";
  
  std::vector<FaceInfo> sides;
  for (auto& name : {"front", "back", "left", "right"}) {
    if (faceMap.count(name)) sides.push_back(faceMap[name]);
  }
  
  std::vector<FaceInfo> visibles;
  for (auto& s : sides) if (s.dot > 0.01f) visibles.push_back(s);
  
  auto& pool = (visibles.size() >= 2) ? visibles : sides;
  std::sort(pool.begin(), pool.end(), [](const FaceInfo& a, const FaceInfo& b) {
    return a.dot > b.dot;
  });
  
  std::string isoLeft, isoRight;
  if (pool.size() >= 2) {
    if (pool[0].nx > pool[1].nx) {
      isoRight = pool[0].name;
      isoLeft = pool[1].name;
    } else {
      isoRight = pool[1].name;
      isoLeft = pool[0].name;
    }
  }
  
  std::unordered_map<std::string, std::string> faceToRole;
  faceToRole[isoTop] = "top";
  std::unordered_map<std::string, std::string> opposite = {
    {"top", "bottom"}, {"bottom", "top"}, 
    {"left", "right"}, {"right", "left"},
    {"front", "back"}, {"back", "front"}
  };
  if (opposite.count(isoTop)) faceToRole[opposite[isoTop]] = "top";
  if (!isoLeft.empty()) faceToRole[isoLeft] = "left";
  if (!isoRight.empty()) faceToRole[isoRight] = "right";
  
  for (auto& face : data.faces) {
    if (materialMode && isPureColor(face.r, face.g, face.b)) continue;
    
    auto it = faceToRole.find(face.faceName);
    if (it == faceToRole.end()) continue;
    
    std::string role = it->second;
    auto& isoColor = (role == "top") ? topColor : 
                     (role == "left") ? leftColor : rightColor;
    
    if (shadingMode == "alpha") {
      float brightness = isoColor[3] / 255.0f;
      if (enableTint) {
        float tintR = isoColor[0] / 255.0f;
        float tintG = isoColor[1] / 255.0f;
        float tintB = isoColor[2] / 255.0f;
        face.r = (unsigned char)(face.r * brightness * tintR + 0.5f);
        face.g = (unsigned char)(face.g * brightness * tintG + 0.5f);
        face.b = (unsigned char)(face.b * brightness * tintB + 0.5f);
      } else {
        face.r = (unsigned char)(face.r * brightness + 0.5f);
        face.g = (unsigned char)(face.g * brightness + 0.5f);
        face.b = (unsigned char)(face.b * brightness + 0.5f);
      }
    } else {
      face.r = isoColor[0];
      face.g = isoColor[1];
      face.b = isoColor[2];
    }
  }
}

// Shader registry
typedef void (*ShaderFunc)(ShaderData&, const ShaderParams&);
static std::unordered_map<std::string, ShaderFunc> g_lightingShaders = {
  {"basic", shader_basic},
  {"dynamic", shader_dynamic}
};
static std::unordered_map<std::string, ShaderFunc> g_fxShaders = {
  {"faceshade", shader_faceshade},
  {"iso", shader_iso}
};

// ======================== END NATIVE SHADER SYSTEM ========================

// ======================== NEW: OPTIMIZED VISIBILITY SYSTEM ========================
// precompute_visible_faces(xRot, yRot, zRot, orthogonal)
// Returns: { visibleFaces = {front=bool, back=bool, ...}, faceOrder = {"front", "top", ...}, count = 3 }
static int l_precompute_visible_faces(lua_State* L) {
  double xr = lua_isnumber(L, 1) ? lua_tonumber(L, 1) : 0.0;
  double yr = lua_isnumber(L, 2) ? lua_tonumber(L, 2) : 0.0;
  double zr = lua_isnumber(L, 3) ? lua_tonumber(L, 3) : 0.0;
  // bool orthogonal = lua_toboolean(L, 4); // Not needed for face visibility
  
  const double RX = xr * PI/180.0;
  const double RY = yr * PI/180.0;
  const double RZ = zr * PI/180.0;
  const double cx = std::cos(RX), sx = std::sin(RX);
  const double cy = std::cos(RY), sy = std::sin(RY);
  const double cz = std::cos(RZ), sz = std::sin(RZ);
  
  // Camera view direction (looking down +Z after rotation)
  double viewX = 0, viewY = 0, viewZ = 1;
  
  struct Face { const char* name; double nx, ny, nz; };
  static const Face faces[] = {
    {"front",  0, 0, 1}, {"back",   0, 0,-1}, {"right", 1, 0, 0},
    {"left",  -1, 0, 0}, {"top",    0, 1, 0}, {"bottom",0,-1, 0}
  };
  
  struct VisibleFace {
    const char* name;
    double dot;
  };
  std::vector<VisibleFace> visibleFaces;
  
  const double threshold = 0.01;
  
  for (auto &f : faces) {
    double x1 = f.nx, y1 = f.ny, z1 = f.nz;
    // Rotate normal
    { double y2 = y1*cx - z1*sx; double z2 = y1*sx + z1*cx; y1 = y2; z1 = z2; }
    { double x2 = x1*cy + z1*sy; double z3 = -x1*sy + z1*cy; x1 = x2; z1 = z3; }
    { double x3 = x1*cz - y1*sz; double y3 = x1*sz + y1*cz; x1 = x3; y1 = y3; }
    
    double dot = x1*viewX + y1*viewY + z1*viewZ;
    
    if (dot > threshold) {
      visibleFaces.push_back({f.name, dot});
    }
  }
  
  // Sort by depth (back to front): smaller dot = further back
  std::sort(visibleFaces.begin(), visibleFaces.end(), 
    [](const VisibleFace& a, const VisibleFace& b) { return a.dot < b.dot; });
  
  // Build result table
  lua_createtable(L, 0, 3); // {visibleFaces, faceOrder, count}
  
  // visibleFaces = {front=true, back=false, ...}
  lua_createtable(L, 0, 6);
  for (auto &f : faces) {
    bool visible = false;
    for (auto &vf : visibleFaces) {
      if (strcmp(vf.name, f.name) == 0) {
        visible = true;
        break;
      }
    }
    lua_pushboolean(L, visible);
    lua_setfield(L, -2, f.name);
  }
  lua_setfield(L, -2, "visibleFaces");
  
  // faceOrder = {"back", "top", "front"} (sorted by depth)
  lua_createtable(L, visibleFaces.size(), 0);
  for (size_t i = 0; i < visibleFaces.size(); i++) {
    lua_pushstring(L, visibleFaces[i].name);
    lua_rawseti(L, -2, i + 1); // Lua arrays are 1-indexed
  }
  lua_setfield(L, -2, "faceOrder");
  
  // count = number of visible faces
  lua_pushinteger(L, visibleFaces.size());
  lua_setfield(L, -2, "count");
  
  return 1;
}

// precompute_rotated_normals(xRot, yRot, zRot)
// Returns: { front = {x,y,z}, back = {x,y,z}, ... } (6 rotated normals for lighting)
static int l_precompute_rotated_normals(lua_State* L) {
  double xr = lua_isnumber(L, 1) ? lua_tonumber(L, 1) : 0.0;
  double yr = lua_isnumber(L, 2) ? lua_tonumber(L, 2) : 0.0;
  double zr = lua_isnumber(L, 3) ? lua_tonumber(L, 3) : 0.0;
  
  const double RX = xr * PI/180.0;
  const double RY = yr * PI/180.0;
  const double RZ = zr * PI/180.0;
  const double cx = std::cos(RX), sx = std::sin(RX);
  const double cy = std::cos(RY), sy = std::sin(RY);
  const double cz = std::cos(RZ), sz = std::sin(RZ);
  
  struct Face { const char* name; double nx, ny, nz; };
  static const Face faces[] = {
    {"front",  0, 0, 1}, {"back",   0, 0,-1}, {"right", 1, 0, 0},
    {"left",  -1, 0, 0}, {"top",    0, 1, 0}, {"bottom",0,-1, 0}
  };
  
  lua_createtable(L, 0, 6);
  
  for (auto &f : faces) {
    double x1 = f.nx, y1 = f.ny, z1 = f.nz;
    // Rotate normal
    { double y2 = y1*cx - z1*sx; double z2 = y1*sx + z1*cx; y1 = y2; z1 = z2; }
    { double x2 = x1*cy + z1*sy; double z3 = -x1*sy + z1*cy; x1 = x2; z1 = z3; }
    { double x3 = x1*cz - y1*sz; double y3 = x1*sz + y1*cz; x1 = x3; y1 = y3; }
    
    // Create {x, y, z} table for this normal
    lua_createtable(L, 0, 3);
    lua_pushnumber(L, x1); lua_setfield(L, -2, "x");
    lua_pushnumber(L, y1); lua_setfield(L, -2, "y");
    lua_pushnumber(L, z1); lua_setfield(L, -2, "z");
    lua_setfield(L, -2, f.name);
  }
  
  return 1;
}

// precompute_unit_cube_vertices(xRot, yRot, zRot)
// Returns: array of 8 rotated unit cube vertices {{x,y,z}, ...}
static int l_precompute_unit_cube_vertices(lua_State* L) {
  double xr = lua_isnumber(L, 1) ? lua_tonumber(L, 1) : 0.0;
  double yr = lua_isnumber(L, 2) ? lua_tonumber(L, 2) : 0.0;
  double zr = lua_isnumber(L, 3) ? lua_tonumber(L, 3) : 0.0;
  
  const double RX = xr * PI/180.0;
  const double RY = yr * PI/180.0;
  const double RZ = zr * PI/180.0;
  const double cx = std::cos(RX), sx = std::sin(RX);
  const double cy = std::cos(RY), sy = std::sin(RY);
  const double cz = std::cos(RZ), sz = std::sin(RZ);
  
  // Unit cube vertices (8 corners)
  static const double unitCube[8][3] = {
    {0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 1, 0}, // Front face
    {0, 0, 1}, {1, 0, 1}, {1, 1, 1}, {0, 1, 1}  // Back face
  };
  
  lua_createtable(L, 8, 0); // Array of 8 vertices
  
  for (int i = 0; i < 8; i++) {
    double x = unitCube[i][0], y = unitCube[i][1], z = unitCube[i][2];
    
    // Rotate vertex
    { double y2 = y*cx - z*sx; double z2 = y*sx + z*cx; y = y2; z = z2; }
    { double x2 = x*cy + z*sy; double z3 = -x*sy + z*cy; x = x2; z = z3; }
    { double x3 = x*cz - y*sz; double y3 = x*sz + y*cz; x = x3; y = y3; }
    
    lua_createtable(L, 0, 3);
    lua_pushnumber(L, x); lua_setfield(L, -2, "x");
    lua_pushnumber(L, y); lua_setfield(L, -2, "y");
    lua_pushnumber(L, z); lua_setfield(L, -2, "z");
    lua_rawseti(L, -2, i + 1); // 1-indexed
  }
  
  return 1;
}

// ======================== END OPTIMIZED VISIBILITY SYSTEM ========================

} // anonymous namespace

static const luaL_Reg FUNCS[] = {
  {"transform_voxel", l_transform_voxel},
  {"calculate_face_visibility", l_calculate_face_visibility},
  {"render_basic", l_render_basic},
  // NEW: Optimized precompute functions
  {"precompute_visible_faces", l_precompute_visible_faces},
  {"precompute_rotated_normals", l_precompute_rotated_normals},
  {"precompute_unit_cube_vertices", l_precompute_unit_cube_vertices},
  // Phase 4: stack shading renderer (updated implementation)
  {"render_stack", [](lua_State* L)->int {
      if(!lua_istable(L,1)||!lua_istable(L,2)){
        lua_pushnil(L); lua_pushstring(L,"expected (voxels, params)"); return 2;
      }
      int width  =(int)getNum(L,2,"width",200);
      int height =(int)getNum(L,2,"height",200);
      float scale=(float)getNum(L,2,"scale",-12345.0f);
      if (scale < 0) scale=(float)getNum(L,2,"scaleLevel",1.0f);
      if (scale <= 0) scale = 1.0f;
      float xRotDeg=(float)getNum(L,2,"xRotation",0.0f);
      float yRotDeg=(float)getNum(L,2,"yRotation",0.0f);
      float zRotDeg=(float)getNum(L,2,"zRotation",0.0f);
      float fovDeg =(float)getNum(L,2,"fovDegrees",0.0f);
      lua_getfield(L,2,"orthogonal"); bool orth = lua_toboolean(L,-1)!=0; lua_pop(L,1);
      std::string perspRef="middle";
      lua_getfield(L,2,"perspectiveScaleRef");
      if(lua_isstring(L,-1)){ perspRef = lua_tostring(L,-1); }
      lua_pop(L,1);
      unsigned char bgR=0,bgG=0,bgB=0,bgA=0;
      lua_getfield(L,2,"backgroundColor");
      if(lua_istable(L,-1)){
        bgR=(unsigned char)getFieldInteger(L,-1,"r",0);
        bgG=(unsigned char)getFieldInteger(L,-1,"g",0);
        bgB=(unsigned char)getFieldInteger(L,-1,"b",0);
        bgA=(unsigned char)getFieldInteger(L,-1,"a",0);
      }
      lua_pop(L,1);

      struct Module {
        std::string shape;
        std::string type;
        std::string scope;
        bool tintAlpha=false;
        bool hasMaterial=false;
        unsigned char matR=0,matG=0,matB=0,matA=255;
        std::vector<std::array<unsigned char,4>> colors;
      };
      std::vector<Module> modules;
      lua_getfield(L,2,"fxStack");
      if(lua_istable(L,-1)){
        lua_getfield(L,-1,"modules");
        if(lua_istable(L,-1)){
          size_t mcount=lua_rawlen(L,-1);
          for(size_t i=1;i<=mcount;i++){
            lua_rawgeti(L,-1,(int)i);
            if(lua_istable(L,-1)){
              Module M;
              lua_getfield(L,-1,"shape"); if(lua_isstring(L,-1)) M.shape=lua_tostring(L,-1); lua_pop(L,1);
              lua_getfield(L,-1,"type"); if(lua_isstring(L,-1)) M.type=lua_tostring(L,-1); lua_pop(L,1);
              lua_getfield(L,-1,"scope"); if(lua_isstring(L,-1)) M.scope=lua_tostring(L,-1); lua_pop(L,1);
              lua_getfield(L,-1,"tintAlpha"); M.tintAlpha=lua_toboolean(L,-1)!=0; lua_pop(L,1);
              if(M.scope=="material"){
                lua_getfield(L,-1,"materialColor");
                if(lua_istable(L,-1)){
                  M.hasMaterial=true;
                  M.matR=(unsigned char)getFieldInteger(L,-1,"r",255);
                  M.matG=(unsigned char)getFieldInteger(L,-1,"g",255);
                  M.matB=(unsigned char)getFieldInteger(L,-1,"b",255);
                  M.matA=(unsigned char)getFieldInteger(L,-1,"a",255);
                }
                lua_pop(L,1);
              }
              lua_getfield(L,-1,"colors");
              if(lua_istable(L,-1)){
                size_t cc=lua_rawlen(L,-1);
                for(size_t ci=1;ci<=cc;ci++){
                  lua_rawgeti(L,-1,(int)ci);
                  if(lua_istable(L,-1)){
                    unsigned char r=(unsigned char)getFieldInteger(L,-1,"r",255);
                    unsigned char g=(unsigned char)getFieldInteger(L,-1,"g",255);
                    unsigned char b=(unsigned char)getFieldInteger(L,-1,"b",255);
                    unsigned char a=(unsigned char)getFieldInteger(L,-1,"a",255);
                    M.colors.push_back({{r,g,b,a}});
                  }
                  lua_pop(L,1);
                }
              }
              lua_pop(L,1);
              modules.push_back(std::move(M));
            }
            lua_pop(L,1);
          }
        }
        lua_pop(L,1);
      }
      lua_pop(L,1); // fxStack
      
      size_t count=lua_rawlen(L,1);
      lua_createtable(L,0,3);
      if(count==0){
        lua_pushinteger(L,width); lua_setfield(L,-2,"width");
        lua_pushinteger(L,height); lua_setfield(L,-2,"height");
        lua_pushlstring(L,"",0); lua_setfield(L,-2,"pixels");
        return 1;
      }
      std::vector<Voxel> voxels;
      voxels.reserve(count);
      float minX=1e9f,minY=1e9f,minZ=1e9f;
      float maxX=-1e9f,maxY=-1e9f,maxZ=-1e9f;
      for(size_t i=1;i<=count;i++){
        lua_rawgeti(L,1,(int)i);
        if(lua_istable(L,-1)){
          int tblIdx = lua_gettop(L);
          Voxel v{0,0,0,255,255,255,255};
          // detect numeric form
          lua_rawgeti(L,tblIdx,1);
          bool numeric = lua_isnumber(L,-1)!=0;
          lua_pop(L,1);
          if(numeric){
            lua_rawgeti(L,tblIdx,1); v.x=(float)lua_tonumber(L,-1); lua_pop(L,1);
            lua_rawgeti(L,tblIdx,2); v.y=(float)lua_tonumber(L,-1); lua_pop(L,1);
            lua_rawgeti(L,tblIdx,3); v.z=(float)lua_tonumber(L,-1); lua_pop(L,1);
            lua_rawgeti(L,tblIdx,4); v.r=(unsigned char)lua_tointeger(L,-1); lua_pop(L,1);
            lua_rawgeti(L,tblIdx,5); v.g=(unsigned char)lua_tointeger(L,-1); lua_pop(L,1);
            lua_rawgeti(L,tblIdx,6); v.b=(unsigned char)lua_tointeger(L,-1); lua_pop(L,1);
            lua_rawgeti(L,tblIdx,7); v.a=(unsigned char)lua_tointeger(L,-1); lua_pop(L,1);
          } else {
            v.x=(float)getNum(L,tblIdx,"x",0);
            v.y=(float)getNum(L,tblIdx,"y",0);
            v.z=(float)getNum(L,tblIdx,"z",0);
            lua_getfield(L,tblIdx,"color");
            if(lua_istable(L,-1)){
              v.r=(unsigned char)getFieldInteger(L,-1,"r",255);
              v.g=(unsigned char)getFieldInteger(L,-1,"g",255);
              v.b=(unsigned char)getFieldInteger(L,-1,"b",255);
              v.a=(unsigned char)getFieldInteger(L,-1,"a",255);
            }
            lua_pop(L,1);
          }
          if(v.x<minX)minX=v.x; if(v.x>maxX)maxX=v.x;
          if(v.y<minY)minY=v.y; if(v.y>maxY)maxY=v.y;
          if(v.z<minZ)minZ=v.z; if(v.z>maxZ)maxZ=v.z;
          voxels.push_back(v);
        }
        lua_pop(L,1);
      }
      float midX=0.5f*(minX+maxX);
      float midY=0.5f*(minY+maxY);
      float midZ=0.5f*(minZ+maxZ);
      float sizeX=maxX-minX+1.f;
      float sizeY=maxY-minY+1.f;
      float sizeZ=maxZ-minZ+1.f;
      float maxDim=std::max(sizeX,std::max(sizeY,sizeZ));

      float RX=xRotDeg*(float)PI/180.f;
      float RY=yRotDeg*(float)PI/180.f;
      float RZ=zRotDeg*(float)PI/180.f;
      float cx=std::cos(RX), sx=std::sin(RX);
      float cy=std::cos(RY), sy=std::sin(RY);
      float cz=std::cos(RZ), sz=std::sin(RZ);

      // ----------------------------------------------------------------------------
      // PERSPECTIVE & ORTHOGRAPHIC CAMERA (MATCH previewRenderer.lua)
      //   - Stronger FOV warping: camera distance shrinks non‑linearly as FOV increases
      //   - Reference depth scaling: chosen perspectiveScaleRef ("front","middle","back")
      //     stays closest to the user scale while allowing other depths to warp.
      //   - Orthographic path simplified (no template voxelSize distortion).
      // ----------------------------------------------------------------------------
      bool perspective = (!orth && fovDeg > 0.f);
      float focalLength = 0.f;
      float camDist;
      if (perspective) {
        // Clamp FOV and compute warp curve -> amplified factor
        fovDeg = std::max(5.f, std::min(75.f, fovDeg));
        float warpT = (fovDeg - 5.f) / (75.f - 5.f);
        if (warpT < 0.f) warpT = 0.f; if (warpT > 1.f) warpT = 1.f;
        float amplified = std::pow(warpT, 1.f/3.f);
        const float BASE_NEAR = 1.2f;
        const float FAR_EXTRA = 45.f;
        camDist = maxDim * (BASE_NEAR + (1.f - amplified)*(1.f - amplified) * FAR_EXTRA);
        float fovRad = fovDeg * (float)PI / 180.f;
        focalLength = (height / 2.f) / std::tan(fovRad / 2.f);
      } else {
        camDist = maxDim * 5.f;
      }

      // Calibrated voxel size
      float voxelSize;
      {
        float maxAllowed = std::min(width,height)*0.9f;
        if (perspective && focalLength>1e-6f && maxDim>0.f){
          // Rotate AABB corners to derive front/back depths (match basic renderer)
          float rcx=cx, rsx=sx, rcy=cy, rsy=sy, rcz=cz, rsz=sz;
          float zMin =  1e9f;
          float zMax = -1e9f;
          for(int ix=0;ix<2;ix++){
            float Xv=(ix?maxX:minX)-midX;
            for(int iy=0;iy<2;iy++){
              float Yv=(iy?maxY:minY)-midY;
              for(int iz=0;iz<2;iz++){
                float Zv=(iz?maxZ:minZ)-midZ;
                { float Y2=Yv*rcx - Zv*rsx; float Z2=Yv*rsx + Zv*rcx; Yv=Y2; Zv=Z2; }
                { float X2=Xv*rcy + Zv*rsy; float Z3=-Xv*rsy + Zv*rcy; Xv=X2; Zv=Z3; }
                { float X3=Xv*rcz - Yv*rsz; float Y3=Xv*rsz + Yv*rcz; Xv=X3; Yv=Y3; }
                float worldZ = Zv + midZ;
                if (worldZ < zMin) zMin = worldZ;
                if (worldZ > zMax) zMax = worldZ;
              }
            }
          }
          float cameraZ   = midZ + camDist;
          float depthBack  = std::max(0.001f, cameraZ - zMin); // farthest
          float depthFront = std::max(0.001f, cameraZ - zMax); // nearest
          float depthMiddle= std::max(0.001f, camDist);        // model center
          float depthRef = depthMiddle;
          if (perspRef=="front"||perspRef=="Front") depthRef = depthFront;
          else if (perspRef=="back"||perspRef=="Back") depthRef = depthBack;
          voxelSize = scale * (depthRef / focalLength);
          if (voxelSize * maxDim > maxAllowed) voxelSize = maxAllowed / maxDim;
          if (voxelSize <= 0.f) voxelSize = 1.f;
        } else {
          voxelSize=scale;
          if(voxelSize<1) voxelSize=1;
          float maxAllowed = std::min(width,height)*0.9f;
          if(voxelSize*maxDim>maxAllowed) voxelSize*= (maxAllowed/(voxelSize*maxDim));
        }
      }
      float thresholdBase=0.01f/std::min(3.f,voxelSize);

      // Face basis + rotation helper
      struct BF { const char* name; float nx,ny,nz; };
      BF baseFaces[6]={
        {"front",0,0,1},{"back",0,0,-1},{"right",1,0,0},
        {"left",-1,0,0},{"top",0,1,0},{"bottom",0,-1,0}
      };
      auto rotateN=[&](float &x,float &y,float &z){
        float y2=y*cx - z*sx; float z2=y*sx + z*cx; y=y2; z=z2;
        float x2=x*cy + z*sy; float z3=-x*sy + z*cy; x=x2; z=z3;
        float x3=x*cz - y*sz; float y3=x*sz + y*cz; x=x3; y=y3;
      };
      struct RN { std::string face; float nx,ny,nz,dot; };
      std::vector<RN> rns;
      for(auto &bf: baseFaces){
        float nx=bf.nx,ny=bf.ny,nz=bf.nz;
        rotateN(nx,ny,nz);
        float mag=std::sqrt(nx*nx+ny*ny+nz*nz);
        if(mag>1e-6f){ nx/=mag; ny/=mag; nz/=mag; }
        float dot = nz; // viewDir (0,0,1)
        rns.push_back({bf.name,nx,ny,nz,dot});
      }
      std::string isoTop = (rns[4].dot >= rns[5].dot) ? "top" : "bottom";
      std::vector<RN> sides;
      for(auto &rn: rns)
        if(rn.face=="front"||rn.face=="back"||rn.face=="left"||rn.face=="right")
          sides.push_back(rn);
      std::vector<RN> vis;
      for(auto &s: sides) if(s.dot>0) vis.push_back(s);
      auto &pool = vis.size()>=2? vis : sides;
      std::sort(pool.begin(), pool.end(), [](const RN&a,const RN&b){return a.dot>b.dot;});
      std::string isoLeft, isoRight;
      if(pool.size()>=2){
        RN s1=pool[0], s2=pool[1];
        if(s1.nx > s2.nx){ isoRight=s1.face; isoLeft=s2.face; }
        else { isoRight=s2.face; isoLeft=s1.face; }
      }
      auto opposite=[&](const std::string& f)->std::string{
        if (f == "top") return "bottom";
        if (f == "bottom") return "top";
        if (f == "left") return "right";
        if (f == "right") return "left";
        if (f == "front") return "back";
        return "front";
      };

      struct ColorKey{
        unsigned char r,g,b,a;
        bool operator==(const ColorKey&o)const{
          return r==o.r&&g==o.g&&b==o.b&&a==o.a;
        }
      };
      struct CKHash{
        size_t operator()(const ColorKey&k) const noexcept{
          return k.r ^ (k.g<<8) ^ (k.b<<16) ^ (k.a<<24);
        }
      };
      struct FaceColors {
        std::array<std::array<unsigned char,4>,6> faceRGBA;
      };
      std::unordered_map<ColorKey, FaceColors, CKHash> shadeCache;

      auto applyModules=[&](unsigned char r,unsigned char g,unsigned char b,unsigned char a,
                            const std::string& face)->std::array<unsigned char,4>{
        unsigned char outR=r,outG=g,outB=b,outA=a;
        for(const auto &M: modules){
          if(M.scope=="material" && M.hasMaterial){
            if(!(r==M.matR && g==M.matG && b==M.matB && a==M.matA)) continue;
          }
          int idx=-1;
          if(M.shape=="FaceShade"){
            if(face=="top") idx=1;
            else if(face=="bottom") idx=0;
            else if(face=="front") idx=2;
            else if(face=="back")  idx=3;
            else if(face=="left")  idx=4;
            else if(face=="right") idx=5;
          } else if(M.shape=="Iso"){
            if(face==isoTop || face==opposite(isoTop)) idx=0;
            else if(face==isoLeft) idx=1;
            else if(face==isoRight) idx=2;
            else if(face=="front"||face=="back"){
              if(!isoLeft.empty()) idx=1;
              else if(!isoRight.empty()) idx=2;
            }
          }
          if(idx<0 || (size_t)idx>=M.colors.size()) continue;
          auto col = M.colors[idx];
          if(M.type=="literal"){
            outR = col[0]; outG = col[1]; outB = col[2];
          } else { // alpha style brightness
            float alphaNorm = col[3]/255.f;
            float minB=0.2f;
            float bright=minB + (1.f-minB)*alphaNorm;
            outR=(unsigned char)std::min(255.f, outR*bright);
            outG=(unsigned char)std::min(255.f, outG*bright);
            outB=(unsigned char)std::min(255.f, outB*bright);
            if(M.tintAlpha){
              outR=(unsigned char)std::min(255.f, outR*(col[0]/255.f));
              outG=(unsigned char)std::min(255.f, outG*(col[1]/255.f));
              outB=(unsigned char)std::min(255.f, outB*(col[2]/255.f));
            }
          }
        }
        return {{outR,outG,outB,outA}};
      };

      struct FacePolyLocal{
        float x[4],y[4],depth;
        unsigned char r,g,b,a;
      };
      std::vector<FacePolyLocal> polys;
      polys.reserve(voxels.size()*6);

      float screenCX=width*0.5f;
      float screenCY=height*0.5f;
      float camZ = midZ + camDist;

      for(auto &v: voxels){
        float x=v.x-midX, y=v.y-midY, z=v.z-midZ;
        { float y2=y*cx - z*sx; float z2=y*sx + z*cx; y=y2; z=z2; }
        { float x2=x*cy + z*sy; double z3=-x*sy + z*cy; x=x2; z=(float)z3; }
        { float x3=x*cz - y*sz; float y3=x*sz + y*cz; x=x3; y=y3; }
        float worldX=x+midX, worldY=y+midY, worldZ=z+midZ;

        float vxv,vyv,vzv;
        if(orth){
          vxv=0.f; vyv=0.f; vzv=1.f; // stable orthographic view vector
        } else {
          vxv=midX-worldX; vyv=midY-worldY; vzv=camZ-worldZ;
          float m=std::sqrt(vxv*vxv+vyv*vyv+vzv*vzv);
          if(m>1e-5f){ vxv/=m; vyv/=m; vzv/=m; }
        }

        const char* faceNames[6] = {"front","back","right","left","top","bottom"};
        ColorKey key{v.r,v.g,v.b,v.a};
        FaceColors fc;
        auto itShade = shadeCache.find(key);
        if(itShade == shadeCache.end()){
          for(int fi=0; fi<6; ++fi){
            auto col = applyModules(v.r,v.g,v.b,v.a, std::string(faceNames[fi]));
            fc.faceRGBA[fi] = {{ col[0], col[1], col[2], col[3] }};
          }
          shadeCache.emplace(key, fc);
        } else {
          fc = itShade->second;
        }
        for(int f=0;f<6;f++){
          float nx=LOCAL_FACE_NORMALS[f][0];
          float ny=LOCAL_FACE_NORMALS[f][1];
          float nz=LOCAL_FACE_NORMALS[f][2];
          // rotate normal (reuse rotateN logic)
          {
            float y2=ny*cx - nz*sx; float z2=ny*sx + nz*cx; ny=y2; nz=z2;
            float x2=nx*cy + nz*sy; float z3=-nx*sy + nz*cy; nx=x2; nz=z3;
            float x3=nx*cz - ny*sz; float y3=nx*sz + ny*cz; nx=x3; ny=y3;
          }
          float dot = nx*vxv + ny*vyv + nz*vzv;
          if(dot <= thresholdBase) continue;

          FacePolyLocal poly{};
          auto rgba=fc.faceRGBA[f];
          poly.r=rgba[0]; poly.g=rgba[1]; poly.b=rgba[2]; poly.a=rgba[3];
          float avgDepth=0.f;
          for(int vi=0;vi<4;vi++){
            int vid=FACE_IDX[f][vi]-1;
            float lx=UNIT_VERTS[vid][0]*voxelSize;
            float ly=UNIT_VERTS[vid][1]*voxelSize;
            float lz=UNIT_VERTS[vid][2]*voxelSize;
            { float y2=ly*cx - lz*sx; float z2=ly*sx + lz*cx; ly=y2; lz=z2; }
            { float x2=lx*cy + lz*sy; float z3=-lx*sy + lz*cy; lx=x2; lz=z3; }
            { float x3=lx*cz - ly*sz; float y3=lx*sz + ly*cz; lx=x3; ly=y3; }
            float wx=worldX*voxelSize + lx;
            float wy=worldY*voxelSize + ly;
            float wz=worldZ + (lz/voxelSize);
            if(perspective){
              float depth=(camZ - wz);
              if(depth<0.001f) depth=0.001f;
              float s=focalLength>0? (focalLength/depth):1.f;
              poly.x[vi]=screenCX + (wx - midX*voxelSize)*s;
              poly.y[vi]=screenCY + (wy - midY*voxelSize)*s;
              avgDepth += depth;
            } else {
              poly.x[vi]=screenCX + (wx - midX*voxelSize);
              poly.y[vi]=screenCY + (wy - midY*voxelSize);
              avgDepth += (camZ - worldZ);
            }
          }
          poly.depth=avgDepth/4.f;
          polys.push_back(poly);
        }
      }

      std::sort(polys.begin(),polys.end(),[](const FacePolyLocal&a,const FacePolyLocal&b){
        return a.depth > b.depth;
      });

      std::vector<unsigned char> buffer((size_t)width*height*4,0);
      for(int y=0;y<height;y++){
        for(int x=0;x<width;x++){
          size_t off=((size_t)y*width + x)*4;
          buffer[off+0]=bgR; buffer[off+1]=bgG; buffer[off+2]=bgB; buffer[off+3]=bgA;
        }
      }
      for(auto &p: polys){
        FacePoly polyOut;
        for(int i=0;i<4;i++){ polyOut.x[i]=p.x[i]; polyOut.y[i]=p.y[i]; }
        polyOut.depth=p.depth; polyOut.r=p.r; polyOut.g=p.g; polyOut.b=p.b; polyOut.a=p.a;
        rasterQuad(polyOut,width,height,buffer);
      }

      lua_pushinteger(L,width); lua_setfield(L,-2,"width");
      lua_pushinteger(L,height); lua_setfield(L,-2,"height");
      lua_pushlstring(L,(const char*)buffer.data(), buffer.size()); lua_setfield(L,-2,"pixels");
      return 1;
  }},
  // --------------------------------------------------------------------------
  // DYNAMIC LIGHTING RENDERER (Lambert + exponent, ambient, radial falloff,
  // rim lighting)
  // --------------------------------------------------------------------------
  {"render_dynamic", [](lua_State* L)->int {
      if(!lua_istable(L,1)||!lua_istable(L,2)){
        lua_pushnil(L); lua_pushstring(L,"expected (voxels, params)"); return 2;
      }
      int width  =(int)getNum(L,2,"width",200);
      int height =(int)getNum(L,2,"height",200);
      float scale=(float)getNum(L,2,"scale",-12345.0f);
      if (scale < 0) scale=(float)getNum(L,2,"scaleLevel",1.0f);
      if (scale <= 0) scale = 1.f;
      float xRotDeg=(float)getNum(L,2,"xRotation",0.0f);
      float yRotDeg=(float)getNum(L,2,"yRotation",0.0f);
      float zRotDeg=(float)getNum(L,2,"zRotation",0.0f);
      float fovDeg =(float)getNum(L,2,"fovDegrees",0.0f);
      lua_getfield(L,2,"orthogonal"); bool orth = lua_toboolean(L,-1)!=0; lua_pop(L,1);
      std::string perspRef="middle";
      lua_getfield(L,2,"perspectiveScaleRef");
      if(lua_isstring(L,-1)){ perspRef = lua_tostring(L,-1); }
      lua_pop(L,1);
      unsigned char bgR=0,bgG=0,bgB=0,bgA=0;
      lua_getfield(L,2,"backgroundColor");
      if(lua_istable(L,-1)){
        bgR=(unsigned char)getFieldInteger(L,-1,"r",0);
        bgG=(unsigned char)getFieldInteger(L,-1,"g",0);
        bgB=(unsigned char)getFieldInteger(L,-1,"b",0);
        bgA=(unsigned char)getFieldInteger(L,-1,"a",0);
      }
      lua_pop(L,1);

      // Lighting params
      float pitch=0.f,yaw=0.f,diffusePct=60.f,diameterPct=100.f,ambientPct=30.f;
      bool rimEnabled=false;
      unsigned char lR=255,lG=255,lB=255;
      lua_getfield(L,2,"lighting");
      if(lua_istable(L,-1)){
        pitch =(float)getNum(L,-1,"pitch",0.0);
        yaw   =(float)getNum(L,-1,"yaw",0.0);
        diffusePct =(float)getNum(L,-1,"diffuse",60.0);
        diameterPct=(float)getNum(L,-1,"diameter",100.0);
        ambientPct =(float)getNum(L,-1,"ambient",30.0);
        lua_getfield(L,-1,"rimEnabled"); rimEnabled = lua_toboolean(L,-1)!=0; lua_pop(L,1);
        lua_getfield(L,-1,"lightColor");
        if(lua_istable(L,-1)){
          lR=(unsigned char)getFieldInteger(L,-1,"r",255);
          lG=(unsigned char)getFieldInteger(L,-1,"g",255);
          lB=(unsigned char)getFieldInteger(L,-1,"b",255);
        }
        lua_pop(L,1);
      }
      lua_pop(L,1);

      // Voxels
      size_t vcount=lua_rawlen(L,1);
      std::vector<Voxel> voxels;
      voxels.reserve(vcount);
      float minX=1e9f,minY=1e9f,minZ=1e9f;
      float maxX=-1e9f,maxY=-1e9f,maxZ=-1e9f;
      for(size_t i=1;i<=vcount;i++){
        lua_rawgeti(L,1,(int)i);
        if(lua_istable(L,-1)){
          int t=lua_gettop(L);
          Voxel v{0,0,0,255,255,255,255};
          lua_rawgeti(L,t,1); bool numeric=lua_isnumber(L,-1)!=0; lua_pop(L,1);
          if(numeric){
            lua_rawgeti(L,t,1); v.x=(float)lua_tonumber(L,-1); lua_pop(L,1);
            lua_rawgeti(L,t,2); v.y=(float)lua_tonumber(L,-1); lua_pop(L,1);
            lua_rawgeti(L,t,3); v.z=(float)lua_tonumber(L,-1); lua_pop(L,1);
            lua_rawgeti(L,t,4); v.r=(unsigned char)lua_tointeger(L,-1); lua_pop(L,1);
            lua_rawgeti(L,t,5); v.g=(unsigned char)lua_tointeger(L,-1); lua_pop(L,1);
            lua_rawgeti(L,t,6); v.b=(unsigned char)lua_tointeger(L,-1); lua_pop(L,1);
            lua_rawgeti(L,t,7); v.a=(unsigned char)lua_tointeger(L,-1); lua_pop(L,1);
          } else {
            v.x=(float)getNum(L,t,"x",0);
            v.y=(float)getNum(L,t,"y",0);
            v.z=(float)getNum(L,t,"z",0);
            lua_getfield(L,t,"color");
            if(lua_istable(L,-1)){
              v.r=(unsigned char)getFieldInteger(L,-1,"r",255);
              v.g=(unsigned char)getFieldInteger(L,-1,"g",255);
              v.b=(unsigned char)getFieldInteger(L,-1,"b",255);
              v.a=(unsigned char)getFieldInteger(L,-1,"a",255);
            }
            lua_pop(L,1);
          }
          if(v.x<minX)minX=v.x; if(v.x>maxX)maxX=v.x;
          if(v.y<minY)minY=v.y; if(v.y>maxY)maxY=v.y;
          if(v.z<minZ)minZ=v.z; if(v.z>maxZ)maxZ=v.z;
          voxels.push_back(v);
        }
        lua_pop(L,1);
      }

      lua_createtable(L,0,3);
      if(voxels.empty()){
        lua_pushinteger(L,width); lua_setfield(L,-2,"width");
        lua_pushinteger(L,height); lua_setfield(L,-2,"height");
        lua_pushlstring(L,"",0); lua_setfield(L,-2,"pixels");
        return 1;
      }

      float midX=0.5f*(minX+maxX);
      float midY=0.5f*(minY+maxY);
      float midZ=0.5f*(minZ+maxZ);
      float sizeX=maxX-minX+1.f;
      float sizeY=maxY-minY+1.f;
      float sizeZ=maxZ-minZ+1.f;
      float maxDim=std::max(sizeX,std::max(sizeY,sizeZ));

      float RX=xRotDeg*(float)PI/180.f;
      float RY=yRotDeg*(float)PI/180.f;
      float RZ=zRotDeg*(float)PI/180.f;
      float cx=std::cos(RX), sx=std::sin(RX);
      float cy=std::cos(RY), sy=std::sin(RY);
      float cz=std::cos(RZ), sz=std::sin(RZ);

      // ----------------------------------------------------------------------------
      // PERSPECTIVE & ORTHOGRAPHIC CAMERA (MATCH previewRenderer.lua)
      //   - Stronger FOV warping: camera distance shrinks non‑linearly as FOV increases
      //   - Reference depth scaling: chosen perspectiveScaleRef ("front","middle","back")
      //     stays closest to the user scale while allowing other depths to warp.
      //   - Orthographic path simplified (no template voxelSize distortion).
      // ----------------------------------------------------------------------------
      bool perspective = (!orth && fovDeg > 0.f);
      float focalLength = 0.f;
      float camDist;
      if (perspective) {
        // Clamp FOV and compute warp curve -> amplified factor
        fovDeg = std::max(5.f, std::min(75.f, fovDeg));
        float warpT = (fovDeg - 5.f) / (75.f - 5.f);
        if (warpT < 0.f) warpT = 0.f; if (warpT > 1.f) warpT = 1.f;
        float amplified = std::pow(warpT, 1.f/3.f);
        const float BASE_NEAR = 1.2f;
        const float FAR_EXTRA = 45.f;
        camDist = maxDim * (BASE_NEAR + (1.f - amplified)*(1.f - amplified) * FAR_EXTRA);
        float fovRad = fovDeg * (float)PI / 180.f;
        focalLength = (height / 2.f) / std::tan(fovRad / 2.f);
      } else {
        camDist = maxDim * 5.f;
      }

      // Compute voxelSize
      float voxelSize = scale;
      {
        float maxAllowedPixels = std::min(width, height) * 0.9f;
        if (perspective && focalLength > 1e-6f && maxDim > 0.f) {
          // Rotate AABB corners to derive front/back depths (match basic renderer)
          float RX = xRotDeg*(float)PI/180.f;
          float RY = yRotDeg*(float)PI/180.f;
          float RZ = zRotDeg*(float)PI/180.f;
          float rcx=std::cos(RX), rsx=std::sin(RX);
          float rcy=std::cos(RY), rsy=std::sin(RY);
          float rcz=std::cos(RZ), rsz=std::sin(RZ);
          float zMinRot =  1e9f;
          float zMaxRot = -1e9f;
          for (int ix=0; ix<2; ++ix){
            float cxv = (ix==0)?minX:maxX;
            for (int iy=0; iy<2; ++iy){
              float cyv = (iy==0)?minY:maxY;
              for (int iz=0; iz<2; ++iz){
                float czv = (iz==0)?minZ:maxZ;
                float X = cxv - midX;
                float Y = cyv - midY;
                float Z = czv - midZ;
                { float Y2=Y*rcx - Z*rsx; float Z2=Y*rsx + Z*rcx; Y=Y2; Z=Z2; }
                { float X2=X*rcy + Z*rsy; float Z3=-X*rsy + Z*rcy; X=X2; Z=Z3; }
                { float X3=X*rcz - Y*rsz; float Y3=X*rsz + Y*rcz; X=X3; Y=Y3; }
                float worldZ = Z + midZ;
                if (worldZ < zMinRot) zMinRot = worldZ;
                if (worldZ > zMaxRot) zMaxRot = worldZ;
              }
            }
          }
          float cameraZ = midZ + camDist;
          float depthBack  = std::max(0.001f, cameraZ - zMinRot); // farthest
          float depthFront = std::max(0.001f, cameraZ - zMaxRot); // nearest
          float depthMiddle= std::max(0.001f, camDist);        // model center
          float depthRef = depthMiddle;
          if (perspRef == "front" || perspRef == "Front") depthRef = depthFront;
          else if (perspRef == "back" || perspRef == "Back") depthRef = depthBack;
          voxelSize = scale * (depthRef / focalLength);
          if (voxelSize * maxDim > maxAllowedPixels) voxelSize = maxAllowedPixels / maxDim;
          if (voxelSize <= 0.f) voxelSize = 1.f;
        } else {
          if (voxelSize < 1.f) voxelSize = 1.f;
          if (voxelSize * maxDim > maxAllowedPixels && maxDim > 0.f)
            voxelSize *= (maxAllowedPixels / (voxelSize * maxDim));
        }
      }
      float threshold = 0.01f / std::min(3.0f, voxelSize);

      // Light direction
      float yawRad = yaw*(float)PI/180.f;
      float pitchRad = pitch*(float)PI/180.f;
      float cosYaw=std::cos(yawRad), sinYaw=std::sin(yawRad);
      float cosPitch=std::cos(pitchRad), sinPitch=std::sin(pitchRad);
      float Lx = cosYaw * cosPitch;
      float Ly = sinPitch;
      float Lz = sinYaw * cosPitch;
      float Lmag=std::sqrt(Lx*Lx+Ly*Ly+Lz*Lz);
      if(Lmag>1e-6f){ Lx/=Lmag; Ly/=Lmag; Lz/=Lmag; }

      auto rotateVecCam=[&](float &x,float &y,float &z){
        float y2=y*cx - z*sx; float z2=y*sx + z*cx; y=y2; z=z2;
        float x2=x*cy + z*sy; float z3=-x*sy + z*cy; x=x2; z=z3;
        float x3=x*cz - y*sz; float y3=x*sz + y*cz; x=x3; y=y3;
      };

      struct RFace { float nx,ny,nz; };
      RFace faceNormals[6];
      for(int f=0;f<6;f++){
        float nx=LOCAL_FACE_NORMALS[f][0];
        float ny=LOCAL_FACE_NORMALS[f][1];
        float nz=LOCAL_FACE_NORMALS[f][2];
        rotateVecCam(nx,ny,nz);
        float m=std::sqrt(nx*nx+ny*ny+nz*nz);
        if(m>1e-6f){ nx/=m; ny/=m; nz/=m; }
        faceNormals[f]={nx,ny,nz};
      }

      auto rotateAxis=[&](float x,float y,float z){
        rotateVecCam(x,y,z);
        return std::array<float,3>{x,y,z};
      };
      auto ex=rotateAxis(1,0,0);
      auto ey=rotateAxis(0,1,0);
      auto ez=rotateAxis(0,0,1);
      float Lmx = ex[0]*Lx + ey[0]*Ly + ez[0]*Lz;
      float Lmy = ex[1]*Lx + ey[1]*Ly + ez[1]*Lz;
      float Lmz = ex[2]*Lx + ey[2]*Ly + ez[2]*Lz;
      float Lmm=std::sqrt(Lmx*Lmx+Lmy*Lmy+Lmz*Lmz);
      if(Lmm>1e-6f){ Lmx/=Lmm; Lmy/=Lmm; Lmz/=Lmm; }

      float diag = std::sqrt(sizeX*sizeX + sizeY*sizeY + sizeZ*sizeZ);
      float modelRadius = 0.5f * diag;
      float dia = std::max(0.f, diameterPct/100.f);
      float baseRadius = dia * modelRadius;
      float diffNorm = diffusePct/100.f;
      float coreRadius = baseRadius * std::max(0.f, (1.f - 0.4f*diffNorm));

      float exponent = 5.f - 4.f * diffNorm;
      if (exponent < 0.2f) exponent = 0.2f;
      float ambient = 0.02f + 0.48f * (ambientPct/100.f);
      if (ambient > 1.f) ambient = 1.f; if (ambient < 0.f) ambient = 0.f;
      float lightCr = (float)lR / 255.f;
      float lightCg = (float)lG / 255.f;
      float lightCb = (float)lB / 255.f;

      struct Poly { float x[4],y[4],depth; unsigned char r,g,b,a; };
      std::vector<Poly> polys;
      polys.reserve(voxels.size()*6);
      float screenCX=width*0.5f;
      float screenCY=height*0.5f;
      float camZ = midZ + camDist;

      for(auto &v: voxels){
        float x=v.x-midX, y=v.y-midY, z=v.z-midZ;
        { float y2=y*cx - z*sx; float z2=y*sx + z*cx; y=y2; z=z2; }
        { float x2=x*cy + z*sy; double z3=-x*sy + z*cy; x=x2; z=(float)z3; }
        { float x3=x*cz - y*sz; float y3=x*sz + y*cz; x=x3; y=y3; }
        float worldX=x+midX, worldY=y+midY, worldZ=z+midZ;

        float vxv,vyv,vzv;
        if(orth){ vxv=0.f; vyv=0.f; vzv=1.f; }
        else {
          vxv=midX-worldX; vyv=midY-worldY; vzv=camZ-worldZ;
          float m=std::sqrt(vxv*vxv+vyv*vyv+vzv*vzv);
          if(m>1e-5f){ vxv/=m; vyv/=m; vzv/=m; }
        }

        float mvx=v.x-midX, mvy=v.y-midY, mvz=v.z-midZ;
        float proj = mvx*Lmx + mvy*Lmy + mvz*Lmz;
        float px = mvx - proj*Lmx;
        float py = mvy - proj*Lmy;
        float pz = mvz - proj*Lmz;
        float perp=std::sqrt(px*px+py*py+pz*pz);
        float radial=1.f;
        if(baseRadius>1e-6f){
          if(perp <= coreRadius) radial=1.f;
          else if(perp >= baseRadius) radial=0.f;
          else {
            float t=(perp-coreRadius)/(baseRadius-coreRadius);
            float ss=t*t*(3.f-2.f*t);
            radial=1.f-ss;
          }
        }

        for(int f=0;f<6;f++){
          const auto &fn=faceNormals[f];
          float visDot=fn.nx*vxv + fn.ny*vyv + fn.nz*vzv;
          if(visDot <= threshold) continue;
          float ndotl = fn.nx*Lx + fn.ny*Ly + fn.nz*Lz;
          if(ndotl < 0.f) ndotl=0.f;
          float diff = std::pow(ndotl, exponent) * radial;
          float rF=v.r * (ambient + diff * lightCr);
          float gF=v.g * (ambient + diff * lightCg);
          float bF=v.b * (ambient + diff * lightCb);
          if(rimEnabled){
            float ndotv=fn.nz; // viewDir (0,0,1)
            if(ndotv > 0.f){
              float edge=1.f - ndotv;
              float t;
              if(edge <= 0.55f) t=0.f; else if(edge >= 0.95f) t=1.f;
              else { float tt=(edge-0.55f)/(0.4f); t=tt*tt*(3.f-2.f*tt); }
              if(t>0.f){
                float rimStrength=0.6f;
                float rim=rimStrength*t;
                rF += lightCr * rim * 255.f;
                gF += lightCg * rim * 255.f;
                bF += rimStrength * rim * 255.f;
              }
            }
          }
          if(rF<0) rF=0; if(rF>255) rF=255;
          if(gF<0) gF=0; if(gF>255) gF=255;
          if(bF<0) bF=0; if(bF>255) bF=255;

          Poly poly{};
          poly.r=(unsigned char)std::lround(rF);
          poly.g=(unsigned char)std::lround(gF);
          poly.b=(unsigned char)std::lround(bF);
          poly.a=v.a;
          float avgDepth=0.f;
          for(int vi=0;vi<4;vi++){
            int vid=FACE_IDX[f][vi]-1;
            float lx=UNIT_VERTS[vid][0]*voxelSize;
            float ly=UNIT_VERTS[vid][1]*voxelSize;
            float lz=UNIT_VERTS[vid][2]*voxelSize;
            { float y2=ly*cx - lz*sx; float z2=ly*sx + lz*cx; ly=y2; lz=z2; }
            { float x2=lx*cy + lz*sy; float z3=-lx*sy + lz*cy; lx=x2; lz=z3; }
            { float x3=lx*cz - ly*sz; float y3=lx*sz + ly*cz; lx=x3; ly=y3; }
            float wx=worldX*voxelSize + lx;
            float wy=worldY*voxelSize + ly;
            float wz=worldZ + (lz/voxelSize);
            if(perspective){
              float depth=(camZ - wz);
              if(depth<0.001f) depth=0.001f;
              float s=focalLength>0? (focalLength/depth):1.f;
              poly.x[vi]=screenCX + (wx - midX*voxelSize)*s;
              poly.y[vi]=screenCY + (wy - midY*voxelSize)*s;
              avgDepth += depth;
            } else {
              poly.x[vi]=screenCX + (wx - midX*voxelSize);
              poly.y[vi]=screenCY + (wy - midY*voxelSize);
              avgDepth += (camZ - worldZ);
            }
          }
          poly.depth=avgDepth/4.f;
          polys.push_back(poly);
        }
      }

      std::sort(polys.begin(),polys.end(),[](const Poly&a,const Poly&b){
        return a.depth > b.depth;
      });

      std::vector<unsigned char> buffer((size_t)width*height*4,0);
      for(int y=0;y<height;y++){
        for(int x=0;x<width;x++){
          size_t off=((size_t)y*width + x)*4;
          buffer[off+0]=bgR; buffer[off+1]=bgG; buffer[off+2]=bgB; buffer[off+3]=bgA;
        }
      }
      for(auto &p: polys){
        FacePoly polyOut;
        for(int i=0;i<4;i++){ polyOut.x[i]=p.x[i]; polyOut.y[i]=p.y[i]; }
        polyOut.depth=p.depth; polyOut.r=p.r; polyOut.g=p.g; polyOut.b=p.b; polyOut.a=p.a;
        rasterQuad(polyOut,width,height,buffer);
      }
      lua_pushinteger(L,width); lua_setfield(L,-2,"width");
      lua_pushinteger(L,height); lua_setfield(L,-2,"height");
      lua_pushlstring(L,(const char*)buffer.data(), buffer.size()); lua_setfield(L,-2,"pixels");
      return 1;
  }},
  
  // --------------------------- SHADER STACK RENDERER (NEW) -----------------------
  // render_with_shaders(voxelModel, params, shaderStack)
  // Executes Lua shader pipeline from C++ for maximum performance
  {"render_with_shaders", [](lua_State* L) -> int {
    // Validate arguments
    if (!lua_istable(L, 1)) {
      lua_pushnil(L);
      lua_pushstring(L, "arg 1 (voxelModel) must be table");
      return 2;
    }
    if (!lua_istable(L, 2)) {
      lua_pushnil(L);
      lua_pushstring(L, "arg 2 (params) must be table");
      return 2;
    }
    if (!lua_istable(L, 3)) {
      lua_pushnil(L);
      lua_pushstring(L, "arg 3 (shaderStack) must be table");
      return 2;
    }
    
    // Get parameters
    lua_getfield(L, 2, "width");
    int width = lua_tointeger(L, -1);
    lua_pop(L, 1);
    
    lua_getfield(L, 2, "height");
    int height = lua_tointeger(L, -1);
    lua_pop(L, 1);
    
    if (width <= 0 || height <= 0) {
      lua_pushnil(L);
      lua_pushstring(L, "width and height must be > 0");
      return 2;
    }
    
    // Read voxel model
    std::vector<Voxel> voxels;
    lua_pushnil(L);
    while (lua_next(L, 1) != 0) {
      if (lua_istable(L, -1)) {
        Voxel v;
        v.x = (float)getNum(L, -1, "x", 0.0);
        v.y = (float)getNum(L, -1, "y", 0.0);
        v.z = (float)getNum(L, -1, "z", 0.0);
        
        // Get color
        lua_getfield(L, -1, "color");
        if (lua_istable(L, -1)) {
          v.r = (unsigned char)getNum(L, -1, "r", 255);
          v.g = (unsigned char)getNum(L, -1, "g", 255);
          v.b = (unsigned char)getNum(L, -1, "b", 255);
          v.a = (unsigned char)getNum(L, -1, "a", 255);
        } else {
          v.r = v.g = v.b = v.a = 255;
        }
        lua_pop(L, 1);
        
        voxels.push_back(v);
      }
      lua_pop(L, 1);
    }
    
    if (voxels.empty()) {
      lua_pushnil(L);
      lua_pushstring(L, "no voxels in model");
      return 2;
    }
    
    // Get rotation parameters
    double xRot = getNum(L, 2, "xRotation", 0.0);
    double yRot = getNum(L, 2, "yRotation", 0.0);
    double zRot = getNum(L, 2, "zRotation", 0.0);
    double scale = getNum(L, 2, "scale", 1.0);
    
    lua_getfield(L, 2, "orthogonal");
    bool orthogonal = lua_toboolean(L, -1);
    lua_pop(L, 1);
    
    // Calculate middle point
    float minX = voxels[0].x, maxX = voxels[0].x;
    float minY = voxels[0].y, maxY = voxels[0].y;
    float minZ = voxels[0].z, maxZ = voxels[0].z;
    
    for (const auto& v : voxels) {
      if (v.x < minX) minX = v.x;
      if (v.x > maxX) maxX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.y > maxY) maxY = v.y;
      if (v.z < minZ) minZ = v.z;
      if (v.z > maxZ) maxZ = v.z;
    }
    
    float midX = (minX + maxX) / 2.0f;
    float midY = (minY + maxY) / 2.0f;
    float midZ = (minZ + maxZ) / 2.0f;
    
    // Rotation matrices
    const double RX = xRot * PI / 180.0;
    const double RY = yRot * PI / 180.0;
    const double RZ = zRot * PI / 180.0;
    const double cx = std::cos(RX), sx = std::sin(RX);
    const double cy = std::cos(RY), sy = std::sin(RY);
    const double cz = std::cos(RZ), sz = std::sin(RZ);
    
    // Face definitions
    struct FaceInfo {
      const char* name;
      float nx, ny, nz;
      int indices[4];
    };
    
    const FaceInfo faces[] = {
      {"front",  0, 0, 1,  {0,1,2,3}},
      {"back",   0, 0, -1, {5,4,7,6}},
      {"right",  1, 0, 0,  {1,5,6,2}},
      {"left",  -1, 0, 0,  {4,0,3,7}},
      {"top",    0, 1, 0,  {3,2,6,7}},
      {"bottom", 0, -1, 0, {4,5,1,0}}
    };
    
    // Cube vertices (centered at 0,0,0)
    const float cubeVerts[8][3] = {
      {-0.5f, -0.5f, -0.5f}, {0.5f, -0.5f, -0.5f},
      {0.5f, 0.5f, -0.5f}, {-0.5f, 0.5f, -0.5f},
      {-0.5f, -0.5f, 0.5f}, {0.5f, -0.5f, 0.5f},
      {0.5f, 0.5f, 0.5f}, {-0.5f, 0.5f, 0.5f}
    };
    
    // Build face list with shader application
    std::vector<FacePoly> polys;
    polys.reserve(voxels.size() * 6);
    
    const float projDist = 100.0f;
    const float halfW = width / 2.0f;
    const float halfH = height / 2.0f;
    
    for (const auto& voxel : voxels) {
      for (const auto& face : faces) {
        // Transform face normal
        float nx = face.nx, ny = face.ny, nz = face.nz;
        float ny2 = ny * cx - nz * sx;
        float nz2 = ny * sx + nz * cx;
        ny = ny2; nz = nz2;
        
        float nx2 = nx * cy + nz * sy;
        float nz3 = -nx * sy + nz * cy;
        nx = nx2; nz = nz3;
        
        float nx3 = nx * cz - ny * sz;
        float ny3 = nx * sz + ny * cz;
        nx = nx3; ny = ny3;
        
        // Backface culling
        if (nz <= 0.0f) continue;
        
        // Build face quad
        FacePoly poly;
        float avgDepth = 0.0f;
        
        for (int vi = 0; vi < 4; vi++) {
          const float* vert = cubeVerts[face.indices[vi]];
          float x = voxel.x + vert[0] - midX;
          float y = voxel.y + vert[1] - midY;
          float z = voxel.z + vert[2] - midZ;
          
          // Rotate
          float y2 = y * cx - z * sx;
          float z2 = y * sx + z * cx;
          y = y2; z = z2;
          
          float x2 = x * cy + z * sy;
          float z3 = -x * sy + z * cy;
          x = x2; z = z3;
          
          float x3 = x * cz - y * sz;
          float y3 = x * sz + y * cz;
          x = x3; y = y3;
          
          // Project
          if (orthogonal) {
            poly.x[vi] = halfW + x * scale;
            poly.y[vi] = halfH - y * scale;
          } else {
            float factor = projDist / std::max(0.01f, projDist - z);
            poly.x[vi] = halfW + x * scale * factor;
            poly.y[vi] = halfH - y * scale * factor;
          }
          
          avgDepth += (projDist - z);
        }
        poly.depth = avgDepth / 4.0f;
        
        // Apply Lua shader stack to this face
        // Build shaderData table and call shader.process() for each shader
        
        // Create shaderData table
        lua_newtable(L); // shaderData
        
        // shaderData.faces = { {voxel=..., face=..., normal=..., color=...} }
        lua_newtable(L); // faces array
        lua_pushinteger(L, 1);
        lua_newtable(L); // face table
        
        // face.voxel = {x, y, z, color}
        lua_newtable(L);
        lua_pushnumber(L, voxel.x); lua_setfield(L, -2, "x");
        lua_pushnumber(L, voxel.y); lua_setfield(L, -2, "y");
        lua_pushnumber(L, voxel.z); lua_setfield(L, -2, "z");
        lua_newtable(L);
        lua_pushinteger(L, voxel.r); lua_setfield(L, -2, "r");
        lua_pushinteger(L, voxel.g); lua_setfield(L, -2, "g");
        lua_pushinteger(L, voxel.b); lua_setfield(L, -2, "b");
        lua_pushinteger(L, voxel.a); lua_setfield(L, -2, "a");
        lua_setfield(L, -2, "color");
        lua_setfield(L, -2, "voxel");
        
        // face.face = "front" (face name)
        lua_pushstring(L, face.name);
        lua_setfield(L, -2, "face");
        
        // face.normal = {x, y, z} (rotated normal)
        lua_newtable(L);
        lua_pushnumber(L, nx); lua_setfield(L, -2, "x");
        lua_pushnumber(L, ny); lua_setfield(L, -2, "y");
        lua_pushnumber(L, nz); lua_setfield(L, -2, "z");
        lua_setfield(L, -2, "normal");
        
        // face.color = voxel.color (initial)
        lua_newtable(L);
        lua_pushinteger(L, voxel.r); lua_setfield(L, -2, "r");
        lua_pushinteger(L, voxel.g); lua_setfield(L, -2, "g");
        lua_pushinteger(L, voxel.b); lua_setfield(L, -2, "b");
        lua_pushinteger(L, voxel.a); lua_setfield(L, -2, "a");
        lua_setfield(L, -2, "color");
        
        lua_settable(L, -3); // faces[1] = face
        lua_setfield(L, -2, "faces"); // shaderData.faces = faces
        
        // shaderData.camera = params
        lua_pushvalue(L, 2);
        lua_setfield(L, -2, "camera");
        
        // shaderData.params = shaderStack.params
        lua_getfield(L, 3, "params");
        lua_setfield(L, -2, "params");
        
        // Execute lighting shaders (bottom-to-top)
        lua_getfield(L, 3, "lighting");
        if (lua_istable(L, -1)) {
          int lightingCount = lua_rawlen(L, -1);
          for (int i = lightingCount; i >= 1; i--) {
            lua_rawgeti(L, -1, i);
            if (lua_istable(L, -1)) {
              // Check if enabled
              lua_getfield(L, -1, "enabled");
              bool enabled = true;
              if (lua_isboolean(L, -1)) {
                enabled = lua_toboolean(L, -1);
              }
              lua_pop(L, 1);
              
              if (enabled) {
                // Get shader ID
                lua_getfield(L, -1, "id");
                const char* shaderId = lua_tostring(L, -1);
                lua_pop(L, 1);
                
                if (shaderId) {
                  // Get shader module from registry
                  lua_getglobal(L, "AseVoxel");
                  lua_getfield(L, -1, "render");
                  lua_getfield(L, -1, "shader_stack");
                  lua_getfield(L, -1, "registry");
                  lua_getfield(L, -1, "lighting");
                  lua_getfield(L, -1, shaderId);
                  
                  if (lua_istable(L, -1)) {
                    lua_getfield(L, -1, "process");
                    if (lua_isfunction(L, -1)) {
                      // Call shader.process(shaderData, params)
                      lua_pushvalue(L, -8); // shaderData
                      lua_getfield(L, 3, "params");
                      
                      if (lua_pcall(L, 2, 1, 0) == LUA_OK) {
                        // Replace shaderData with result
                        lua_replace(L, -8);
                      } else {
                        lua_pop(L, 1); // error
                      }
                    } else {
                      lua_pop(L, 1);
                    }
                  }
                  lua_pop(L, 6); // shader, lighting, registry, shader_stack, render, AseVoxel
                }
              }
            }
            lua_pop(L, 1); // shader entry
          }
        }
        lua_pop(L, 1); // lighting
        
        // Execute FX shaders (bottom-to-top)
        lua_getfield(L, 3, "fx");
        if (lua_istable(L, -1)) {
          int fxCount = lua_rawlen(L, -1);
          for (int i = fxCount; i >= 1; i--) {
            lua_rawgeti(L, -1, i);
            if (lua_istable(L, -1)) {
              // Check if enabled
              lua_getfield(L, -1, "enabled");
              bool enabled = true;
              if (lua_isboolean(L, -1)) {
                enabled = lua_toboolean(L, -1);
              }
              lua_pop(L, 1);
              
              if (enabled) {
                // Get shader ID
                lua_getfield(L, -1, "id");
                const char* shaderId = lua_tostring(L, -1);
                lua_pop(L, 1);
                
                if (shaderId) {
                  // Get shader module from registry
                  lua_getglobal(L, "AseVoxel");
                  lua_getfield(L, -1, "render");
                  lua_getfield(L, -1, "shader_stack");
                  lua_getfield(L, -1, "registry");
                  lua_getfield(L, -1, "fx");
                  lua_getfield(L, -1, shaderId);
                  
                  if (lua_istable(L, -1)) {
                    lua_getfield(L, -1, "process");
                    if (lua_isfunction(L, -1)) {
                      // Call shader.process(shaderData, params)
                      lua_pushvalue(L, -8); // shaderData
                      lua_getfield(L, 3, "params");
                      
                      if (lua_pcall(L, 2, 1, 0) == LUA_OK) {
                        // Replace shaderData with result
                        lua_replace(L, -8);
                      } else {
                        lua_pop(L, 1); // error
                      }
                    } else {
                      lua_pop(L, 1);
                    }
                  }
                  lua_pop(L, 6); // shader, fx, registry, shader_stack, render, AseVoxel
                }
              }
            }
            lua_pop(L, 1); // shader entry
          }
        }
        lua_pop(L, 1); // fx
        
        // Extract final color from shaderData.faces[1].color
        lua_getfield(L, -1, "faces");
        lua_rawgeti(L, -1, 1);
        lua_getfield(L, -1, "color");
        
        if (lua_istable(L, -1)) {
          poly.r = (unsigned char)getNum(L, -1, "r", voxel.r);
          poly.g = (unsigned char)getNum(L, -1, "g", voxel.g);
          poly.b = (unsigned char)getNum(L, -1, "b", voxel.b);
          poly.a = (unsigned char)getNum(L, -1, "a", voxel.a);
        } else {
          poly.r = voxel.r;
          poly.g = voxel.g;
          poly.b = voxel.b;
          poly.a = voxel.a;
        }
        
        lua_pop(L, 4); // color, face, faces, shaderData
        
        polys.push_back(poly);
      }
    }
    
    // Sort by depth (painter's algorithm)
    std::sort(polys.begin(), polys.end(), [](const FacePoly& a, const FacePoly& b) {
      return a.depth > b.depth;
    });
    
    // Rasterize
    std::vector<unsigned char> buffer((size_t)width * height * 4, 0);
    
    // Clear background
    unsigned char bgR = 240, bgG = 240, bgB = 240, bgA = 255;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        size_t off = ((size_t)y * width + x) * 4;
        buffer[off + 0] = bgR;
        buffer[off + 1] = bgG;
        buffer[off + 2] = bgB;
        buffer[off + 3] = bgA;
      }
    }
    
    // Draw faces
    for (const auto& poly : polys) {
      rasterQuad(poly, width, height, buffer);
    }
    
    // Return result table
    lua_newtable(L);
    lua_pushboolean(L, 1);
    lua_setfield(L, -2, "success");
    
    lua_pushinteger(L, width);
    lua_setfield(L, -2, "width");
    
    lua_pushinteger(L, height);
    lua_setfield(L, -2, "height");
    
    lua_pushinteger(L, polys.size());
    lua_setfield(L, -2, "faceCount");
    
    lua_pushlstring(L, (const char*)buffer.data(), buffer.size());
    lua_setfield(L, -2, "pixels");
    
    return 1;
  }},
  
  {"render_native_shaders", [](lua_State* L)->int {
    // Args: 1=shaderData table, 2=stackConfig table
    if (!lua_istable(L, 1)) return luaL_error(L, "arg1 must be shaderData table");
    if (!lua_istable(L, 2)) return luaL_error(L, "arg2 must be stackConfig table");
    
    // Parse shaderData
    ShaderData data;
    
    // Parse faces array
    lua_getfield(L, 1, "faces");
    if (lua_istable(L, -1)) {
      int faceCount = lua_rawlen(L, -1);
      for (int i = 1; i <= faceCount; i++) {
        lua_rawgeti(L, -1, i);
        if (lua_istable(L, -1)) {
          ShaderFace face;
          
          lua_getfield(L, -1, "voxelX");
          face.voxelX = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 0;
          lua_pop(L, 1);
          
          lua_getfield(L, -1, "voxelY");
          face.voxelY = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 0;
          lua_pop(L, 1);
          
          lua_getfield(L, -1, "voxelZ");
          face.voxelZ = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 0;
          lua_pop(L, 1);
          
          lua_getfield(L, -1, "faceName");
          if (lua_isstring(L, -1)) {
            face.faceName = lua_tostring(L, -1);
          }
          lua_pop(L, 1);
          
          lua_getfield(L, -1, "normalX");
          face.normalX = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 0;
          lua_pop(L, 1);
          
          lua_getfield(L, -1, "normalY");
          face.normalY = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 0;
          lua_pop(L, 1);
          
          lua_getfield(L, -1, "normalZ");
          face.normalZ = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 0;
          lua_pop(L, 1);
          
          lua_getfield(L, -1, "r");
          face.r = lua_isnumber(L, -1) ? (unsigned char)lua_tointeger(L, -1) : 255;
          lua_pop(L, 1);
          
          lua_getfield(L, -1, "g");
          face.g = lua_isnumber(L, -1) ? (unsigned char)lua_tointeger(L, -1) : 255;
          lua_pop(L, 1);
          
          lua_getfield(L, -1, "b");
          face.b = lua_isnumber(L, -1) ? (unsigned char)lua_tointeger(L, -1) : 255;
          lua_pop(L, 1);
          
          lua_getfield(L, -1, "a");
          face.a = lua_isnumber(L, -1) ? (unsigned char)lua_tointeger(L, -1) : 255;
          lua_pop(L, 1);
          
          data.faces.push_back(face);
        }
        lua_pop(L, 1);
      }
    }
    lua_pop(L, 1);
    
    // Parse metadata
    lua_getfield(L, 1, "cameraX");
    data.cameraX = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 0;
    lua_pop(L, 1);
    
    lua_getfield(L, 1, "cameraY");
    data.cameraY = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 0;
    lua_pop(L, 1);
    
    lua_getfield(L, 1, "cameraZ");
    data.cameraZ = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 0;
    lua_pop(L, 1);
    
    lua_getfield(L, 1, "cameraDirX");
    data.cameraDirX = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 0;
    lua_pop(L, 1);
    
    lua_getfield(L, 1, "cameraDirY");
    data.cameraDirY = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 0;
    lua_pop(L, 1);
    
    lua_getfield(L, 1, "cameraDirZ");
    data.cameraDirZ = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 0;
    lua_pop(L, 1);
    
    lua_getfield(L, 1, "middleX");
    data.middleX = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 0;
    lua_pop(L, 1);
    
    lua_getfield(L, 1, "middleY");
    data.middleY = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 0;
    lua_pop(L, 1);
    
    lua_getfield(L, 1, "middleZ");
    data.middleZ = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 0;
    lua_pop(L, 1);
    
    lua_getfield(L, 1, "width");
    data.width = lua_isnumber(L, -1) ? (int)lua_tointeger(L, -1) : 512;
    lua_pop(L, 1);
    
    lua_getfield(L, 1, "height");
    data.height = lua_isnumber(L, -1) ? (int)lua_tointeger(L, -1) : 512;
    lua_pop(L, 1);
    
    lua_getfield(L, 1, "voxelSize");
    data.voxelSize = lua_isnumber(L, -1) ? (float)lua_tonumber(L, -1) : 1;
    lua_pop(L, 1);
    
    // Helper lambda to parse shader params
    auto parseParams = [L](int tableIdx) -> ShaderParams {
      ShaderParams params;
      
      lua_pushnil(L);
      while (lua_next(L, tableIdx) != 0) {
        const char* key = lua_tostring(L, -2);
        if (!key) { lua_pop(L, 1); continue; }
        
        if (lua_isnumber(L, -1)) {
          params.numbers[key] = lua_tonumber(L, -1);
        } else if (lua_isstring(L, -1)) {
          params.strings[key] = lua_tostring(L, -1);
        } else if (lua_isboolean(L, -1)) {
          params.bools[key] = lua_toboolean(L, -1);
        } else if (lua_istable(L, -1)) {
          // Check if it's a color (has r,g,b,a fields)
          lua_getfield(L, -1, "r");
          bool isColor = lua_isnumber(L, -1);
          lua_pop(L, 1);
          
          if (isColor) {
            std::array<unsigned char, 4> color = {255,255,255,255};
            lua_getfield(L, -1, "r");
            if (lua_isnumber(L, -1)) color[0] = (unsigned char)lua_tointeger(L, -1);
            lua_pop(L, 1);
            lua_getfield(L, -1, "g");
            if (lua_isnumber(L, -1)) color[1] = (unsigned char)lua_tointeger(L, -1);
            lua_pop(L, 1);
            lua_getfield(L, -1, "b");
            if (lua_isnumber(L, -1)) color[2] = (unsigned char)lua_tointeger(L, -1);
            lua_pop(L, 1);
            lua_getfield(L, -1, "a");
            if (lua_isnumber(L, -1)) color[3] = (unsigned char)lua_tointeger(L, -1);
            lua_pop(L, 1);
            params.colors[key] = color;
          }
        }
        lua_pop(L, 1);
      }
      return params;
    };
    
    // Execute lighting shaders (bottom to top)
    lua_getfield(L, 2, "lighting");
    if (lua_istable(L, -1)) {
      int lightCount = lua_rawlen(L, -1);
      for (int i = lightCount; i >= 1; i--) {
        lua_rawgeti(L, -1, i);
        if (lua_istable(L, -1)) {
          // Check enabled
          lua_getfield(L, -1, "enabled");
          bool enabled = !lua_isboolean(L, -1) || lua_toboolean(L, -1);
          lua_pop(L, 1);
          
          if (enabled) {
            lua_getfield(L, -1, "id");
            const char* shaderId = lua_tostring(L, -1);
            lua_pop(L, 1);
            
            if (shaderId && g_lightingShaders.count(shaderId)) {
              lua_getfield(L, -1, "params");
              ShaderParams params = parseParams(lua_gettop(L));
              lua_pop(L, 1);
              
              g_lightingShaders[shaderId](data, params);
            }
          }
        }
        lua_pop(L, 1);
      }
    }
    lua_pop(L, 1);
    
    // Execute FX shaders (bottom to top)
    lua_getfield(L, 2, "fx");
    if (lua_istable(L, -1)) {
      int fxCount = lua_rawlen(L, -1);
      for (int i = fxCount; i >= 1; i--) {
        lua_rawgeti(L, -1, i);
        if (lua_istable(L, -1)) {
          // Check enabled
          lua_getfield(L, -1, "enabled");
          bool enabled = !lua_isboolean(L, -1) || lua_toboolean(L, -1);
          lua_pop(L, 1);
          
          if (enabled) {
            lua_getfield(L, -1, "id");
            const char* shaderId = lua_tostring(L, -1);
            lua_pop(L, 1);
            
            if (shaderId && g_fxShaders.count(shaderId)) {
              lua_getfield(L, -1, "params");
              ShaderParams params = parseParams(lua_gettop(L));
              lua_pop(L, 1);
              
              g_fxShaders[shaderId](data, params);
            }
          }
        }
        lua_pop(L, 1);
      }
    }
    lua_pop(L, 1);
    
    // Return modified shaderData
    lua_newtable(L);
    
    // Faces array
    lua_newtable(L);
    for (size_t i = 0; i < data.faces.size(); i++) {
      const auto& face = data.faces[i];
      lua_newtable(L);
      
      lua_pushnumber(L, face.voxelX); lua_setfield(L, -2, "voxelX");
      lua_pushnumber(L, face.voxelY); lua_setfield(L, -2, "voxelY");
      lua_pushnumber(L, face.voxelZ); lua_setfield(L, -2, "voxelZ");
      lua_pushstring(L, face.faceName.c_str()); lua_setfield(L, -2, "faceName");
      lua_pushnumber(L, face.normalX); lua_setfield(L, -2, "normalX");
      lua_pushnumber(L, face.normalY); lua_setfield(L, -2, "normalY");
      lua_pushnumber(L, face.normalZ); lua_setfield(L, -2, "normalZ");
      lua_pushinteger(L, face.r); lua_setfield(L, -2, "r");
      lua_pushinteger(L, face.g); lua_setfield(L, -2, "g");
      lua_pushinteger(L, face.b); lua_setfield(L, -2, "b");
      lua_pushinteger(L, face.a); lua_setfield(L, -2, "a");
      
      lua_rawseti(L, -2, i + 1);
    }
    lua_setfield(L, -2, "faces");
    
    // Copy metadata
    lua_pushnumber(L, data.cameraX); lua_setfield(L, -2, "cameraX");
    lua_pushnumber(L, data.cameraY); lua_setfield(L, -2, "cameraY");
    lua_pushnumber(L, data.cameraZ); lua_setfield(L, -2, "cameraZ");
    lua_pushnumber(L, data.cameraDirX); lua_setfield(L, -2, "cameraDirX");
    lua_pushnumber(L, data.cameraDirY); lua_setfield(L, -2, "cameraDirY");
    lua_pushnumber(L, data.cameraDirZ); lua_setfield(L, -2, "cameraDirZ");
    lua_pushnumber(L, data.middleX); lua_setfield(L, -2, "middleX");
    lua_pushnumber(L, data.middleY); lua_setfield(L, -2, "middleY");
    lua_pushnumber(L, data.middleZ); lua_setfield(L, -2, "middleZ");
    lua_pushinteger(L, data.width); lua_setfield(L, -2, "width");
    lua_pushinteger(L, data.height); lua_setfield(L, -2, "height");
    lua_pushnumber(L, data.voxelSize); lua_setfield(L, -2, "voxelSize");
    
    return 1;
  }},
  
  {nullptr,nullptr}
};

#ifdef _WIN32
  #define ASEVOXEL_API __declspec(dllexport)
#else
  #define ASEVOXEL_API
#endif

extern "C" ASEVOXEL_API int luaopen_asevoxel_native(lua_State* L) {
#if LUA_VERSION_NUM >= 502
  luaL_newlib(L, FUNCS);
#else
  lua_newtable(L);
  for (const luaL_Reg* r=FUNCS; r->name; ++r) {
    lua_pushcfunction(L,r->func);
    lua_setfield(L,-2,r->name);
  }
#endif
  lua_pushstring(L,"0.1.0"); lua_setfield(L,-2,"version");
  lua_pushstring(L,"asevoxel_native"); lua_setfield(L,-2,"name");
  return 1;
}