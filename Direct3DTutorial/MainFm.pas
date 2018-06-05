unit MainFm;
(*
 * Copyright (c) 2018 Yuriy Kotsarenko. All rights reserved.
 * This software is subject to The MIT License.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
 * associated documentation files (the "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
 * following conditions:
 *
 *   The above copyright notice and this permission notice shall be included in all copies or substantial
 *   portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
 * LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *)
interface

uses
  Winapi.Windows, Winapi.D3DCommon, Winapi.DXGIFormat, Winapi.DXGI, Winapi.D3D11, System.Classes,
  System.UITypes, System.Math.Vectors, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs;

type
  TMainForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormPaint(Sender: TObject);
  private
    { Private declarations }
    FFactory: IDXGIFactory1;
    FDevice: ID3D11Device;
    FContext: ID3D11DeviceContext;

    FSwapChainDesc: DXGI_SWAP_CHAIN_DESC;
    FSwapChain: IDXGISwapChain;

    FRenderTargetView: ID3D11RenderTargetView;
    FDepthStencilTexture: ID3D11Texture2D;
    FDepthStencilView: ID3D11DepthStencilView;
    FVertexPositionBuffer: ID3D11Buffer;
    FVertexColorBuffer: ID3D11Buffer;

    FInputLayout: ID3D11InputLayout;
    FVertexShader: ID3D11VertexShader;
    FPixelShader: ID3D11PixelShader;
    FConstantBuffer: ID3D11Buffer;

    procedure ActivateAndClearViewport(const AClearColor: TAlphaColorF);
    procedure UpdateConstantBuffer(const AMatrix: TMatrix3D);
    procedure CreateConstantBuffer;
    procedure CreateShaders;
    procedure CreateVertexBuffer;
    procedure CreateSwapChainViews;
    procedure CreateSwapChain;
    procedure ExtractFactory;
    procedure CreateDevice;
  public
    { Public declarations }
  end;

var
  MainForm: TMainForm;

implementation
{$R *.dfm}

uses
  System.SysUtils, System.Math, System.IOUtils;

const
  // Flags that define what Direct3D feature levels we are going to use.
  AllowedFeatureLevels: array[0..5] of D3D_FEATURE_LEVEL = (D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1,
    D3D_FEATURE_LEVEL_10_0, D3D_FEATURE_LEVEL_9_3, D3D_FEATURE_LEVEL_9_2, D3D_FEATURE_LEVEL_9_1);

  // Flags used for device creation (commonly, to enable debug runtime).
  DeviceCreationFlags = {$IFDEF DEBUG}Ord(D3D11_CREATE_DEVICE_DEBUG){$ELSE}0{$ENDIF};

  // The format in which vertex information is fed into shaders.
  VertexLayout: array[0..1] of D3D11_INPUT_ELEMENT_DESC =
    ((SemanticName: 'POSITION'; SemanticIndex: 0; Format: DXGI_FORMAT_R32G32B32_FLOAT;
      InputSlot: 0; AlignedByteOffset: 0),
    (SemanticName: 'COLOR'; SemanticIndex: 0; Format: DXGI_FORMAT_R8G8B8A8_UNORM;
     InputSlot: 1; AlignedByteOffset: 0));

procedure TMainForm.FormCreate(Sender: TObject);
begin
  try
    CreateDevice;
    ExtractFactory;
    CreateSwapChain;
    CreateSwapChainViews;
    CreateVertexBuffer;
    CreateShaders;
    CreateConstantBuffer;
  except
    on E: Exception do
    begin
      ShowMessage('Exception: ' + E.Message);
      Application.Terminate;
      Exit;
    end;
  end;
end;

procedure TMainForm.FormResize(Sender: TObject);
begin
  if FSwapChain <> nil then
  begin
    FDepthStencilView := nil;
    FDepthStencilTexture := nil;
    FRenderTargetView := nil;

    if Failed(FSwapChain.ResizeBuffers(1, ClientWidth, ClientHeight, FSwapChainDesc.BufferDesc.Format, 0)) then
      raise Exception.Create('Could not resize swap chain.');

    FSwapChainDesc.BufferDesc.Width := ClientWidth;
    FSwapChainDesc.BufferDesc.Height := ClientHeight;
    CreateSwapChainViews;

    Invalidate;
  end;
end;

procedure TMainForm.FormPaint(Sender: TObject);
var
  LWorld, LView, LProjection: TMatrix3D;
  LStride, LOffset: Cardinal;
begin
  if FSwapChain <> nil then
  begin
    // Activate and clear render targets, set current viewport.
    ActivateAndClearViewport(TAlphaColorF.Create(0.075, 0.125, 0.25, 1.0));

    // Activate Vertex and Pixel shaders.
    FContext.IASetInputLayout(FInputLayout);
    FContext.VSSetShader(FVertexShader, nil, 0);
    FContext.PSSetShader(FPixelShader, nil, 0);

    // Define world, view and projection matrices.
    LWorld := TMatrix3D.Identity;

    LView := TMatrix3D.CreateLookAtLH(
      TPoint3D.Create(0.0, 0.0, -200.0), TPoint3D.Zero, TPoint3D.Create(0.0, 1.0, 0.0));

    LProjection := TMatrix3D.CreatePerspectiveFovLH(Pi * 0.25, ClientWidth / ClientHeight, 1.0, 2000.0);

    // Set world / view / projection combined matrix as vertex shader constant.
    UpdateConstantBuffer(LWorld * LView * LProjection);
    FContext.VSSetConstantBuffers(0, 1, FConstantBuffer);

    // Specify vertex buffers.
    LStride := SizeOf(TPoint3D);
    LOffset := 0;
    FContext.IASetVertexBuffers(0, 1, FVertexPositionBuffer, @LStride, @LOffset);

    LStride := SizeOf(TAlphaColor);
    FContext.IASetVertexBuffers(1, 1, FVertexColorBuffer, @LStride, @LOffset);

    // Render the triangle.
    FContext.IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP);
    FContext.Draw(3, 0);

    // Present the scene on screen.
    FSwapChain.Present(Ord(DXGI_SWAP_EFFECT_DISCARD), 0);
  end;
end;

procedure TMainForm.ActivateAndClearViewport(const AClearColor: TAlphaColorF);
var
  LViewport: TD3D11_VIEWPORT;
begin
  FContext.OMSetRenderTargets(1, FRenderTargetView, FDepthStencilView);

  FContext.ClearRenderTargetView(FRenderTargetView, TFourSingleArray(AClearColor));
  FContext.ClearDepthStencilView(FDepthStencilView, Ord(D3D11_CLEAR_DEPTH) or Ord(D3D11_CLEAR_STENCIL),
    1.0, 0);

  FillChar(LViewport, SizeOf(TD3D11_VIEWPORT), 0);
  LViewport.Width := FSwapChainDesc.BufferDesc.Width;
  LViewport.Height := FSwapChainDesc.BufferDesc.Height;
  LViewport.MaxDepth := 1.0;
  FContext.RSSetViewports(1, @LViewport);
end;

procedure TMainForm.UpdateConstantBuffer(const AMatrix: TMatrix3D);
var
  LSubResource: D3D11_MAPPED_SUBRESOURCE;
begin
  if Failed(FContext.Map(FConstantBuffer, 0, D3D11_MAP_WRITE_DISCARD, 0, LSubResource)) then
    raise Exception.Create('Could not map constant buffer.');
  try
    Move(AMatrix, LSubResource.pData^, SizeOf(TMatrix3D));
  finally
    FContext.Unmap(FConstantBuffer, 0);
  end;
end;

procedure TMainForm.CreateConstantBuffer;
var
  FBufferDesc: D3D11_BUFFER_DESC;
begin
  FillChar(FBufferDesc, SizeOf(D3D11_BUFFER_DESC), 0);

  FBufferDesc.ByteWidth := SizeOf(TMatrix3D);
  FBufferDesc.Usage := D3D11_USAGE_DYNAMIC;
  FBufferDesc.BindFlags := Cardinal(D3D11_BIND_CONSTANT_BUFFER);
  FBufferDesc.CPUAccessFlags := Cardinal(D3D11_CPU_ACCESS_WRITE);

  if Failed(FDevice.CreateBuffer(FBufferDesc, nil, FConstantBuffer)) then
    raise Exception.Create('Could not create constant buffer.');
end;

procedure TMainForm.CreateShaders;
var
  LVertexCode, LPixelCode: TBytes;
begin
  LVertexCode := TFile.ReadAllBytes('shaders\simple.vs.bin');
  if Length(LVertexCode) < 1 then
    raise Exception.Create('Could not load vertex shader.');

  if Failed(FDevice.CreateVertexShader(@LVertexCode[0], Length(LVertexCode), nil, @FVertexShader)) then
    raise Exception.Create('Could not create vertex shader.');

  if Failed(FDevice.CreateInputLayout(@VertexLayout[0], Length(VertexLayout), @LVertexCode[0],
    Length(LVertexCode), FInputLayout)) then
    raise Exception.Create('Could not create input layout.');

  LPixelCode := TFile.ReadAllBytes('shaders\simple.ps.bin');
  if Length(LPixelCode) < 1 then
    raise Exception.Create('Could not load pixel shader.');

  if Failed(FDevice.CreatePixelShader(@LPixelCode[0], Length(LPixelCode), nil, FPixelShader)) then
    raise Exception.Create('Could not create pixel shader.');
end;

procedure TMainForm.CreateVertexBuffer;
const
  Vertices: array[0..2] of TPoint3D = (
    (X: -50.0; Y: 40.0; Z: 0.0),
    (X: 50.0; Y: 30.0; Z: 0.0),
    (X: -10.0; Y: -50.0; Z: 0.0));
  Colors: array[0..2] of TAlphaColor = ($FF00FF00, $FFFF0000, $FF0000FF);
var
  FInitialData: D3D11_SUBRESOURCE_DATA;
  FBufferDesc: D3D11_BUFFER_DESC;
begin
  // Point initial data to vertex positions.
  FillChar(FInitialData, SizeOf(D3D11_SUBRESOURCE_DATA), 0);
  FInitialData.pSysMem := @Vertices[0];
  FInitialData.SysMemPitch := SizeOf(TPoint3D);

  // Prepare buffer description for vertex position storage.
  FillChar(FBufferDesc, SizeOf(D3D11_BUFFER_DESC), 0);
  FBufferDesc.ByteWidth := SizeOf(TPoint3D) * 3;
  FBufferDesc.Usage := D3D11_USAGE_IMMUTABLE;
  FBufferDesc.BindFlags := Ord(D3D11_BIND_VERTEX_BUFFER);

  if Failed(FDevice.CreateBuffer(FBufferDesc, @FInitialData, FVertexPositionBuffer)) then
    raise Exception.Create('Could not create vertex position buffer.');

  // Point initial data to vertex colors.
  FInitialData.pSysMem := @Colors[0];
  FInitialData.SysMemPitch := SizeOf(TAlphaColor);

  // Update buffer description for vertex color storage.
  FBufferDesc.ByteWidth := SizeOf(TAlphaColor) * 3;

  if Failed(FDevice.CreateBuffer(FBufferDesc, @FInitialData, FVertexColorBuffer)) then
    raise Exception.Create('Could not create vertex color buffer.');
end;

procedure TMainForm.CreateSwapChainViews;
var
  LBackBuffer: ID3D11Texture2D;
  LDepthStencilDesc: D3D11_TEXTURE2D_DESC;
begin
  // Create Render Target View for an existing back buffer in the swap chain.
  if Failed(FSwapChain.GetBuffer(0, ID3D11Texture2D, LBackBuffer)) then
    raise Exception.Create('Could not retrieve back buffer from DXGI swap chain.');

  if Failed(FDevice.CreateRenderTargetView(LBackBuffer, nil, FRenderTargetView)) then
    raise Exception.Create('Could not create render target view.');

  // Prepare depth/stencil texture description.
  FillChar(LDepthStencilDesc, SizeOf(D3D11_TEXTURE2D_DESC), 0);

  LDepthStencilDesc.Format := DXGI_FORMAT_D24_UNORM_S8_UINT;
  LDepthStencilDesc.Width := FSwapChainDesc.BufferDesc.Width;
  LDepthStencilDesc.Height := FSwapChainDesc.BufferDesc.Height;

  LDepthStencilDesc.MipLevels := 1;
  LDepthStencilDesc.ArraySize := 1;

  LDepthStencilDesc.SampleDesc.Count := FSwapChainDesc.SampleDesc.Count;
  LDepthStencilDesc.SampleDesc.Quality := FSwapChainDesc.SampleDesc.Quality;

  LDepthStencilDesc.Usage := D3D11_USAGE_DEFAULT;
  LDepthStencilDesc.BindFlags := D3D11_BIND_DEPTH_STENCIL;

  if Failed(FDevice.CreateTexture2D(LDepthStencilDesc, nil, FDepthStencilTexture)) then
    raise Exception.Create('Could not create depth stencil texture.');

  if Failed(FDevice.CreateDepthStencilView(FDepthStencilTexture, nil, FDepthStencilView)) then
    raise Exception.Create('Could not create depth stencil view.');
end;

procedure TMainForm.CreateSwapChain;
var
  LSample, LQualityLevels: Cardinal;
begin
  FillChar(FSwapChainDesc, SizeOf(DXGI_SWAP_CHAIN_DESC), 0);

  FSwapChainDesc.BufferCount := 1;
  FSwapChainDesc.BufferDesc.Width := ClientWidth;
  FSwapChainDesc.BufferDesc.Height := ClientHeight;
  FSwapChainDesc.BufferDesc.Format := DXGI_FORMAT_R8G8B8A8_UNORM;
  FSwapChainDesc.BufferUsage := DXGI_USAGE_RENDER_TARGET_OUTPUT;
  FSwapChainDesc.OutputWindow := Handle;
  FSwapChainDesc.Windowed := True;

  // Look for a suitable multisample configuration.
  for LSample := 8 downto 1 do
    if Succeeded(FDevice.CheckMultisampleQualityLevels(FSwapChainDesc.BufferDesc.Format, LSample,
      LQualityLevels)) and (LQualityLevels > 0) then
    begin
      FSwapChainDesc.SampleDesc.Count := LSample;
      FSwapChainDesc.SampleDesc.Quality := LQualityLevels - 1;
      Break;
    end;

  if Failed(FFactory.CreateSwapChain(FDevice, FSwapChainDesc, FSwapChain)) then
    raise Exception.Create('Could not create DXGI swap chain.');
end;

procedure TMainForm.ExtractFactory;
var
  LDevice1: IDXGIDevice1;
  LAdapter1: IDXGIAdapter1;
begin
  if (not Supports(FDevice, IDXGIDevice1, LDevice1)) or
    Failed(LDevice1.GetParent(IDXGIAdapter1, LAdapter1)) or
    Failed(LAdapter1.GetParent(IDXGIFactory1, FFactory)) then
    raise Exception.Create('Could not retrieve DXGI factory.');
end;

procedure TMainForm.CreateDevice;
var
  LFeatureLevel: D3D_FEATURE_LEVEL;
begin
  if Failed(D3D11CreateDevice(nil, D3D_DRIVER_TYPE_HARDWARE, 0, DeviceCreationFlags, @AllowedFeatureLevels[0],
    High(AllowedFeatureLevels) + 1, D3D11_SDK_VERSION, FDevice, LFeatureLevel, FContext)) then
    raise Exception.Create('Could not create Direct3D device.');
end;

initialization
  SetExceptionMask(exAllArithmeticExceptions);

end.
