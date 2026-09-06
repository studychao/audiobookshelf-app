<template>
  <div class="w-full h-full py-6 px-4 overflow-y-auto">
    <p class="mb-4 text-base text-fg">{{ $strings.HeaderDownloads }} ({{ downloadItemParts.length }})</p>
    <div v-if="$platform === 'ios'" class="mb-5"><button class="px-4 py-3 rounded bg-primary text-fg" @click="retry">重试未完成的下载</button><p class="text-sm text-fg-muted mt-2">已完成的文件会保留。网络恢复后可继续下载。</p></div>

    <div v-if="!downloadItemParts.length" class="py-6 text-center text-lg">没有进行中的下载</div>
    <template v-for="(itemPart, num) in downloadItemParts">
      <div :key="itemPart.id" class="w-full">
        <div class="flex">
          <div class="w-14">
            <span v-if="itemPart.failed" class="material-symbols text-error">error</span>
            <span v-else-if="itemPart.completed && itemPart.moved" class="material-symbols text-success">check_circle</span>
            <span v-else class="font-semibold text-fg">{{ Math.round(itemPart.progress) }}%</span>
          </div>
          <div class="flex-grow px-2">
            <p class="break-all">{{ itemPart.filename }}</p>
            <p v-if="itemPart.lastError" class="text-sm text-error">{{ itemPart.lastError }}</p>
          </div>
        </div>

        <div v-if="num + 1 < downloadItemParts.length" class="flex border-t border-border my-3" />
      </div>
    </template>
  </div>
</template>

<script>
import { AbsDownloader } from '@/plugins/capacitor'
export default {
  data() {
    return { restoredItems: [], refreshTimer: null }
  },
  computed: {
    downloadItems() {
      if (this.$platform === 'ios') return this.restoredItems
      const all = new Map(this.restoredItems.map((item) => [item.id, item]))
      this.$store.state.globals.itemDownloads.forEach((item) => all.set(item.id, item))
      return [...all.values()]
    },
    downloadItemParts() {
      let parts = []
      this.downloadItems.forEach((di) => parts.push(...di.downloadItemParts))
      return parts
    }
  },
  methods: {
    async refresh() { if (this.$platform === 'ios') { try { this.restoredItems = (await AbsDownloader.getDownloads()).items } catch (error) { console.warn(error.message) } } },
    async retry() { await AbsDownloader.retryDownloads(); await this.refresh() }
  },
  mounted() { this.refresh(); this.refreshTimer = setInterval(this.refresh, 2000) },
  beforeDestroy() { clearInterval(this.refreshTimer) }
}
</script>
