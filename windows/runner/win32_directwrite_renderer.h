#ifndef RUNNER_WIN32_DIRECTWRITE_RENDERER_H_
#define RUNNER_WIN32_DIRECTWRITE_RENDERER_H_

#include <d2d1.h>
#include <dwrite.h>
#include <windows.h>
#include <wrl/client.h>

#include <string>

class Win32DirectWriteRenderer {
 public:
  static Win32DirectWriteRenderer& Instance();

  bool DrawDirectWriteText(
      HDC context, HWND window, const RECT& target_bounds, const RECT& bounds,
      const std::wstring& text, const std::wstring& font_family,
      float logical_size, DWRITE_FONT_WEIGHT weight, COLORREF color,
      DWRITE_TEXT_ALIGNMENT alignment = DWRITE_TEXT_ALIGNMENT_LEADING,
      DWRITE_PARAGRAPH_ALIGNMENT paragraph_alignment =
          DWRITE_PARAGRAPH_ALIGNMENT_NEAR,
      DWRITE_WORD_WRAPPING word_wrapping = DWRITE_WORD_WRAPPING_EMERGENCY_BREAK,
      float logical_line_spacing_adjustment = 0.0f,
      float logical_offset_y = 0.0f);

  float MeasureTextWidth(
      HWND window, const std::wstring& text, const std::wstring& font_family,
      float logical_size, DWRITE_FONT_WEIGHT weight = DWRITE_FONT_WEIGHT_NORMAL);

 private:
  Win32DirectWriteRenderer();
  ~Win32DirectWriteRenderer();

  Microsoft::WRL::ComPtr<ID2D1Factory> d2d_factory_;
  Microsoft::WRL::ComPtr<IDWriteFactory> write_factory_;
};

#endif  // RUNNER_WIN32_DIRECTWRITE_RENDERER_H_
