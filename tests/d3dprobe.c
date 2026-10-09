/* d3dprobe: create DXGI, D3D11 and D3D12 devices and print what the translation layer reports.
 * No window needed, so it runs headless inside a bottle.
 *
 * build: x86_64-w64-mingw32-gcc -O2 -o d3dprobe.exe d3dprobe.c -ld3d12 -ld3d11 -ldxgi
 * run:   scripts/run.sh tests/d3dprobe.exe
 */
#define COBJMACROS
#include <initguid.h>
#include <windows.h>
#include <stdio.h>
#include <dxgi1_4.h>
#include <d3d11.h>
#include <d3d12.h>

static void print_level(const char *what, D3D_FEATURE_LEVEL level)
{
    printf("%s %x.%x\n", what, (level >> 12) & 0xf, (level >> 8) & 0xf);
}

static void probe_dxgi(void)
{
    IDXGIFactory1 *factory;
    IDXGIAdapter1 *adapter;
    HRESULT hr = CreateDXGIFactory1(&IID_IDXGIFactory1, (void **)&factory);
    UINT i;

    printf("CreateDXGIFactory1: 0x%08lx\n", hr);
    if (FAILED(hr)) return;
    for (i = 0; IDXGIFactory1_EnumAdapters1(factory, i, &adapter) == S_OK; i++)
    {
        DXGI_ADAPTER_DESC1 desc;
        IDXGIAdapter1_GetDesc1(adapter, &desc);
        printf("  adapter %u: %ls (vendor 0x%04x, device 0x%04x, dedicated %llu MB, shared %llu MB)\n",
               i, desc.Description, desc.VendorId, desc.DeviceId,
               (unsigned long long)(desc.DedicatedVideoMemory >> 20),
               (unsigned long long)(desc.SharedSystemMemory >> 20));
        IDXGIAdapter1_Release(adapter);
    }
    IDXGIFactory1_Release(factory);
}

static void probe_d3d11(void)
{
    ID3D11Device *device = NULL;
    D3D_FEATURE_LEVEL level = 0;
    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                                   D3D11_SDK_VERSION, &device, &level, NULL);

    printf("D3D11CreateDevice: 0x%08lx\n", hr);
    if (!device) return;
    print_level("  feature level", level);
    ID3D11Device_Release(device);
}

static void probe_d3d12(void)
{
    static const D3D_FEATURE_LEVEL levels[] =
        {D3D_FEATURE_LEVEL_12_2, D3D_FEATURE_LEVEL_12_1, D3D_FEATURE_LEVEL_12_0, D3D_FEATURE_LEVEL_11_0};
    D3D12_FEATURE_DATA_SHADER_MODEL sm = {D3D_SHADER_MODEL_6_6};
    D3D12_FEATURE_DATA_D3D12_OPTIONS options = {0};
    D3D12_FEATURE_DATA_D3D12_OPTIONS5 options5 = {0};
    ID3D12Device *device = NULL;
    HRESULT hr = E_FAIL;
    unsigned int i;

    for (i = 0; i < ARRAYSIZE(levels); i++)
        if (SUCCEEDED(hr = D3D12CreateDevice(NULL, levels[i], &IID_ID3D12Device, (void **)&device))) break;
    if (FAILED(hr))
    {
        printf("D3D12CreateDevice: 0x%08lx at every feature level\n", hr);
        return;
    }
    print_level("D3D12CreateDevice: ok at feature level", levels[i]);

    hr = ID3D12Device_CheckFeatureSupport(device, D3D12_FEATURE_SHADER_MODEL, &sm, sizeof(sm));
    printf("  highest shader model 0x%x (0x%08lx)\n", sm.HighestShaderModel, hr);
    hr = ID3D12Device_CheckFeatureSupport(device, D3D12_FEATURE_D3D12_OPTIONS, &options, sizeof(options));
    printf("  resource binding tier %d (0x%08lx)\n", options.ResourceBindingTier, hr);
    hr = ID3D12Device_CheckFeatureSupport(device, D3D12_FEATURE_D3D12_OPTIONS5, &options5, sizeof(options5));
    printf("  raytracing tier 0x%x (0x%08lx)\n", options5.RaytracingTier, hr);
    ID3D12Device_Release(device);
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    probe_dxgi();
    probe_d3d11();
    probe_d3d12();
    return 0;
}
