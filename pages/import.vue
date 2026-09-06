<template>
  <div class="personal-import">
    <div class="import-toolbar"><button @click="$router.push('/bookshelf')" aria-label="返回书架">‹ 书架</button><span>添加与整理</span></div>
    <iframe v-if="url" ref="importer" :src="url" title="添加书籍与整理书库" allow="clipboard-write" @load="sendCredentials" />
    <div v-else class="p-6"><p>先连接书库，就可以上传你的音频和电子书。</p><nuxt-link to="/connect" class="text-success">连接书库</nuxt-link></div>
    <p v-if="error" role="alert" class="import-error">{{ error }}</p>
  </div>
</template>
<script>
import { AbsPersonal } from '@/plugins/personal.client'
export default {
  data: () => ({ error: '' }),
  computed: {
    origin() { const address = this.$store.getters['user/getServerAddress']; if (!address) return ''; try { const url = new URL(address); return url.protocol === 'https:' ? url.origin : '' } catch { return '' } },
    url() { return this.origin ? `${this.origin}/personal/` : '' },
    token() { return this.$store.getters['user/getToken'] }
  },
  methods: {
    async sendCredentials() {
      if (!this.token || !this.origin) return
      let files = []
      if (this.$platform === 'ios') { try { files = (await AbsPersonal.listImports()).files } catch (error) { this.error = error.message } }
      this.$refs.importer?.contentWindow.postMessage({ type: 'abs-personal-auth', token: this.token, files }, this.origin)
    },
    async onMessage(event) {
      if (event.origin !== this.origin || event.source !== this.$refs.importer?.contentWindow) return
      const data = event.data
      if (data.type === 'abs-personal-ready') return this.sendCredentials()
      if (data.type === 'abs-personal-complete' && this.$platform === 'ios') {
        await AbsPersonal.removeImports({ ids: data.sharedIds || [] })
        this.$store.commit('personal/update', { importCount: (await AbsPersonal.listImports()).files.length })
      }
      if (data.type === 'abs-personal-read' && this.$platform === 'ios') {
        try { const chunk = await AbsPersonal.readImportChunk({ id: data.id, start: data.start, length: data.length }); event.source.postMessage({ type: 'abs-personal-chunk', requestId: data.requestId, data: chunk.data }, this.origin) }
        catch (error) { event.source.postMessage({ type: 'abs-personal-chunk', requestId: data.requestId, error: error.message }, this.origin) }
      }
    }
  },
  watch: { token() { this.sendCredentials() } },
  mounted() { window.addEventListener('message', this.onMessage) },
  beforeDestroy() { window.removeEventListener('message', this.onMessage) }
}
</script>
<style scoped>
.personal-import{height:100%;display:flex;flex-direction:column;background:#1d2238}.import-toolbar{display:flex;align-items:center;gap:24px;padding:12px 18px;color:#f5f6fa;min-height:52px}.import-toolbar button{font-size:16px;min-height:44px;color:#d8b976}.import-toolbar span{font-size:14px}.personal-import iframe{border:0;flex:1;width:100%;min-height:calc(100vh - 130px)}.import-error{color:#e77f86;padding:14px}
</style>
