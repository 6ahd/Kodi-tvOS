// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once

#include "cores/IPlayer.h"
#include "threads/Thread.h"

#include <atomic>
#include <memory>
#include <mutex>

// DexHub v21: bumps when the Kodi layer above Aether must redraw (subtitle text,
// video size or start). The GUI stays idle otherwise.
unsigned int DexAetherRedrawRevision();
// DexHub v21.43: Picture in Picture for the Aether session that is playing.
// Returns false when the bridge is not loaded (no Aether playback).
bool DexAetherTogglePictureInPicture();

class CTVOSAetherPlayer final : public IPlayer, private CThread
{
public:
  explicit CTVOSAetherPlayer(IPlayerCallback& callback);
  ~CTVOSAetherPlayer() override;
  bool OpenFile(const CFileItem& file, const CPlayerOptions& options) override;
  bool CloseFile(bool reopen = false) override;
  bool IsPlaying() const override;
  bool HasVideo() const override;
  bool HasAudio() const override;
  bool CanSeek() const override;
  void Pause() override;
  void Seek(bool plus, bool large, bool chapter) override;
  void SeekPercentage(float percent) override;
  void SeekTime(int64_t milliseconds) override;
  bool SeekTimeRelative(int64_t milliseconds) override;
  void SetSpeed(float speed) override;
  void SetMute(bool muted) override;
  void SetVolume(float volume) override;
  void SetAVDelay(float delay) override;
  float GetAVDelay() override;
  void SetSubTitleDelay(float delay) override;
  float GetSubTitleDelay() override;
  int GetSubtitleCount() const override;
  int GetSubtitle() override;
  void GetSubtitleStreamInfo(int index, SubtitleStreamInfo& info) const override;
  void SetSubtitle(int index) override;
  bool GetSubtitleVisible() const override;
  void SetSubtitleVisible(bool visible) override;
  void AddSubtitle(const std::string& path) override;
  int GetAudioStreamCount() const override;
  int GetAudioStream() override;
  void GetAudioStreamInfo(int index, AudioStreamInfo& info) const override;
  void SetAudioStream(int index) override;
  int GetVideoStreamCount() const override;
  int GetVideoStream() const override;
  void GetVideoStreamInfo(int index, VideoStreamInfo& info) const override;
  void Render(bool clear, uint32_t alpha, bool gui) override;
  void GetRects(CRect& source, CRect& dest, CRect& view) const override;
  float GetRenderAspectRatio() const override;
  bool IsRenderingVideo() const override;
  bool HasVisibleOverlay() const override;
  bool IsCaching() const override;
  int GetChapterCount() const override;
  int GetChapter() const override;
  void GetChapterName(std::string& name, int chapterIdx = -1) const override;
  int64_t GetChapterPos(int chapterIdx = -1) const override;
  int SeekChapter(int chapter) override;
  void SetSubtitleVerticalPosition(int value, bool save) override;
  void GetAudioCapabilities(std::vector<IPlayerAudioCaps>& caps) const override;
  void GetSubtitleCapabilities(std::vector<IPlayerSubtitleCaps>& caps) const override;
  CVideoSettings GetVideoSettings() const override;
  void SetVideoSettings(CVideoSettings& settings) override;

private:
  void Process() override;
  void Command(const std::string& name, double value = 0, const std::string& text = "");
  struct State;
  static std::string ActiveText(const State& state);
  static int ChapterAt(const State& state);
  std::unique_ptr<State> m_state;
  mutable std::mutex m_lock;
  std::atomic<bool> m_playing{false};
  std::atomic<bool> m_open{false};
};
