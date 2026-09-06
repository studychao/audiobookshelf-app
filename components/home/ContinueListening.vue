<template>
  <section v-if="visible" class="continue-listening" aria-label="继续听书">
    <div class="book-spine" aria-hidden="true">{{ (playback.title || '书').slice(0, 1) }}</div>
    <div class="continue-copy"><p class="eyebrow">继续听</p><h2>{{ playback.title }}</h2><p class="chapter">{{ playback.chapter || playback.author }}</p><p class="remaining">{{ remaining }}</p></div>
    <button :disabled="starting" @click="play" :aria-label="`继续播放 ${playback.title}`"><span class="material-symbols fill">play_arrow</span></button>
  </section>
</template>
<script>
import { AbsAudioPlayer } from '@/plugins/capacitor'
export default {
  data: () => ({ starting: false }),
  computed: {
    playback() { return this.$store.state.personal.playback || {} },
    visible() { return this.playback.id && (this.playback.id.startsWith('local_') || this.playback.serverId === this.$store.state.user.serverConnectionConfig?.id) },
    remaining() { const minutes = Math.ceil(Math.max(0, (this.playback.duration || 0) - (this.playback.position || 0)) / 60 / (this.$store.state.user.settings.playbackRate || 1)); return minutes > 60 ? `还剩 ${Math.floor(minutes / 60)} 小时 ${minutes % 60} 分钟` : `还剩 ${minutes} 分钟` }
  },
  methods: {
    async play() { this.starting = true; try { await AbsAudioPlayer.prepareLibraryItem({ libraryItemId: this.playback.id, episodeId: this.playback.episodeId || null, playWhenReady: true, playbackRate: this.$store.state.user.settings.playbackRate || 1 }) } catch (error) { this.$toast.error(error.message) } finally { this.starting = false } }
  }
}
</script>
<style scoped>
.continue-listening{margin:18px 18px 8px;padding:20px;display:flex;align-items:center;gap:16px;background:#252b46;color:#f5f6fa;border-radius:12px}.book-spine{flex-shrink:0;width:56px;height:82px;border-left:5px solid #8d743f;background:#d8b976;color:#252b46;display:flex;align-items:center;justify-content:center;font-family:"Songti SC",serif;font-size:30px;box-shadow:3px 3px 0 #151a30}.continue-copy{min-width:0;flex:1}.eyebrow{font-size:12px;color:#d8b976;margin-bottom:5px}h2{font-size:18px;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.chapter{font-size:12px;color:#b9bbd0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.remaining{margin-top:8px;font-size:12px;color:#b9bbd0}button{flex-shrink:0;width:48px;height:48px;border-radius:50%;background:#d8b976;color:#252b46;display:flex;align-items:center;justify-content:center}button:focus-visible{outline:3px solid white;outline-offset:3px}button span{font-size:30px}
</style>
