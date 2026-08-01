#include "win32_directwrite_renderer.h"

#include <vector>

Win32DirectWriteRenderer& Win32DirectWriteRenderer::Instance() {
  static Win32DirectWriteRenderer instance;
  return instance;
}

Win32DirectWriteRenderer::Win32DirectWriteRenderer() {
  D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,
                    IID_PPV_ARGS(&d2d_factory_));
  DWriteCreateFactory(
      DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
      reinterpret_cast<IUnknown**>(write_factory_.GetAddressOf()));
}

Win32DirectWriteRenderer::~Win32DirectWriteRenderer() = default;

bool Win32DirectWriteRenderer::DrawDirectWriteText(
    HDC context, HWND window, const RECT& target_bounds, const RECT& bounds,
    const std::wstring& text, const std::wstring& font_family,
    float logical_size, DWRITE_FONT_WEIGHT weight, COLORREF color,
    DWRITE_TEXT_ALIGNMENT alignment,
    DWRITE_PARAGRAPH_ALIGNMENT paragraph_alignment,
    DWRITE_WORD_WRAPPING word_wrapping,
    float logical_line_spacing_adjustment, float logical_offset_y) {
  if (!context || !window || text.empty() || !d2d_factory_ || !write_factory_) {
    return false;
  }

  using Microsoft::WRL::ComPtr;
  D2D1_RENDER_TARGET_PROPERTIES properties = {};
  properties.type = D2D1_RENDER_TARGET_TYPE_DEFAULT;
  properties.pixelFormat.format = DXGI_FORMAT_B8G8R8A8_UNORM;
  properties.pixelFormat.alphaMode = D2D1_ALPHA_MODE_IGNORE;
  properties.dpiX = 96.0f;
  properties.dpiY = 96.0f;
  properties.usage = D2D1_RENDER_TARGET_USAGE_NONE;
  properties.minLevel = D2D1_FEATURE_LEVEL_DEFAULT;
  ComPtr<ID2D1DCRenderTarget> render_target;
  if (FAILED(d2d_factory_->CreateDCRenderTarget(
          &properties, render_target.GetAddressOf()))) {
    return false;
  }

  if (FAILED(render_target->BindDC(context, &target_bounds))) {
    return false;
  }
  render_target->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);

  ComPtr<IDWriteRenderingParams> rendering_params;
  if (SUCCEEDED(write_factory_->CreateCustomRenderingParams(
          2.2f, 1.0f, 0.0f, DWRITE_PIXEL_GEOMETRY_FLAT,
          DWRITE_RENDERING_MODE_NATURAL,
          rendering_params.GetAddressOf()))) {
    render_target->SetTextRenderingParams(rendering_params.Get());
  }

  wchar_t locale_name[LOCALE_NAME_MAX_LENGTH] = {};
  if (GetUserDefaultLocaleName(locale_name,
                               static_cast<int>(std::size(locale_name))) <= 0) {
    wcscpy_s(locale_name, L"zh-CN");
  }
  const UINT dpi = GetDpiForWindow(window) > 0 ? GetDpiForWindow(window) : 96;
  const float physical_size =
      logical_size * static_cast<float>(dpi) / 96.0f;
  ComPtr<IDWriteTextFormat> text_format;
  if (FAILED(write_factory_->CreateTextFormat(
          font_family.c_str(), nullptr, weight, DWRITE_FONT_STYLE_NORMAL,
          DWRITE_FONT_STRETCH_NORMAL, physical_size, locale_name,
          text_format.GetAddressOf()))) {
    return false;
  }
  text_format->SetTextAlignment(alignment);
  text_format->SetParagraphAlignment(paragraph_alignment);
  text_format->SetWordWrapping(word_wrapping);

  const float width = static_cast<float>(bounds.right - bounds.left);
  const float height = static_cast<float>(bounds.bottom - bounds.top);
  ComPtr<IDWriteTextLayout> layout;
  if (FAILED(write_factory_->CreateTextLayout(
          text.c_str(), static_cast<UINT32>(text.size()), text_format.Get(),
          width, height, layout.GetAddressOf()))) {
    return false;
  }
  if (logical_line_spacing_adjustment != 0.0f) {
    DWRITE_LINE_METRICS line_metrics[8] = {};
    UINT32 line_count = 0;
    if (SUCCEEDED(layout->GetLineMetrics(
            line_metrics, static_cast<UINT32>(std::size(line_metrics)),
            &line_count)) &&
        line_count > 0) {
      const float physical_line_spacing_adjustment =
          logical_line_spacing_adjustment * static_cast<float>(dpi) / 96.0f;
      layout->SetLineSpacing(
          DWRITE_LINE_SPACING_METHOD_UNIFORM,
          line_metrics[0].height + physical_line_spacing_adjustment,
          line_metrics[0].baseline);
    }
  }
  DWRITE_TRIMMING trimming = {DWRITE_TRIMMING_GRANULARITY_CHARACTER, 0, 0};
  ComPtr<IDWriteInlineObject> ellipsis;
  if (SUCCEEDED(write_factory_->CreateEllipsisTrimmingSign(
          text_format.Get(), ellipsis.GetAddressOf()))) {
    layout->SetTrimming(&trimming, ellipsis.Get());
  }

  D2D1_COLOR_F brush_color = {
      GetRValue(color) / 255.0f, GetGValue(color) / 255.0f,
      GetBValue(color) / 255.0f, 1.0f};
  ComPtr<ID2D1SolidColorBrush> brush;
  if (FAILED(render_target->CreateSolidColorBrush(
          &brush_color, nullptr, brush.GetAddressOf()))) {
    return false;
  }

  render_target->BeginDraw();
  const float physical_offset_y =
      logical_offset_y * static_cast<float>(dpi) / 96.0f;
  const D2D1_POINT_2F origin = {
      static_cast<float>(bounds.left),
      static_cast<float>(bounds.top) + physical_offset_y};
  render_target->DrawTextLayout(origin, layout.Get(), brush.Get(),
                                D2D1_DRAW_TEXT_OPTIONS_NONE);
  return SUCCEEDED(render_target->EndDraw());
}

float Win32DirectWriteRenderer::MeasureTextWidth(
    HWND window, const std::wstring& text, const std::wstring& font_family,
    float logical_size, DWRITE_FONT_WEIGHT weight) {
  if (!window || text.empty() || !write_factory_) return 0.0f;

  using Microsoft::WRL::ComPtr;
  wchar_t locale_name[LOCALE_NAME_MAX_LENGTH] = {};
  if (GetUserDefaultLocaleName(locale_name,
                               static_cast<int>(std::size(locale_name))) <= 0) {
    wcscpy_s(locale_name, L"zh-CN");
  }
  const UINT dpi = GetDpiForWindow(window) > 0 ? GetDpiForWindow(window) : 96;
  const float physical_size =
      logical_size * static_cast<float>(dpi) / 96.0f;
  ComPtr<IDWriteTextFormat> text_format;
  if (FAILED(write_factory_->CreateTextFormat(
          font_family.c_str(), nullptr, weight, DWRITE_FONT_STYLE_NORMAL,
          DWRITE_FONT_STRETCH_NORMAL, physical_size, locale_name,
          text_format.GetAddressOf()))) {
    return 0.0f;
  }

  ComPtr<IDWriteTextLayout> layout;
  if (FAILED(write_factory_->CreateTextLayout(
          text.c_str(), static_cast<UINT32>(text.size()), text_format.Get(),
          10000.0f, 10000.0f, layout.GetAddressOf()))) {
    return 0.0f;
  }

  DWRITE_TEXT_METRICS metrics = {};
  if (SUCCEEDED(layout->GetMetrics(&metrics))) {
    return metrics.widthIncludingTrailingWhitespace * 96.0f / static_cast<float>(dpi);
  }
  return 0.0f;
}
