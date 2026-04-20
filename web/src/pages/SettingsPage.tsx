import { useTranslation } from 'react-i18next'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import { ProxyConfigPanel } from '@/components/settings/ProxyConfigPanel'
import { ThemePanel } from '@/components/settings/ThemePanel'
import { LanguagePanel } from '@/components/settings/LanguagePanel'
import { DirectoryPanel } from '@/components/settings/DirectoryPanel'
import { BackupPanel } from '@/components/settings/BackupPanel'
import { WebDAVPanel } from '@/components/settings/WebDAVPanel'
import { TerminalPanel } from '@/components/settings/TerminalPanel'
import { WindowPanel } from '@/components/settings/WindowPanel'

export default function SettingsPage() {
  const { t } = useTranslation()

  return (
    <div className="max-w-4xl">
      <h1 className="text-2xl font-bold text-white mb-6">{t('settings.title')}</h1>
      
      <Tabs defaultValue="proxy">
        <TabsList>
          <TabsTrigger value="proxy">{t('settings.proxy')}</TabsTrigger>
          <TabsTrigger value="theme">{t('settings.theme')}</TabsTrigger>
          <TabsTrigger value="language">{t('settings.language')}</TabsTrigger>
          <TabsTrigger value="directory">{t('settings.directory')}</TabsTrigger>
          <TabsTrigger value="backup">{t('settings.backup')}</TabsTrigger>
          <TabsTrigger value="webdav">WebDAV</TabsTrigger>
          <TabsTrigger value="terminal">{t('settings.terminal')}</TabsTrigger>
          <TabsTrigger value="window">{t('settings.window')}</TabsTrigger>
        </TabsList>

        <TabsContent value="proxy">
          <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <ProxyConfigPanel />
          </div>
        </TabsContent>

        <TabsContent value="theme">
          <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <ThemePanel />
          </div>
        </TabsContent>

        <TabsContent value="language">
          <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <LanguagePanel />
          </div>
        </TabsContent>

        <TabsContent value="directory">
          <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <DirectoryPanel />
          </div>
        </TabsContent>

        <TabsContent value="backup">
          <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <BackupPanel />
          </div>
        </TabsContent>

        <TabsContent value="webdav">
          <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <WebDAVPanel />
          </div>
        </TabsContent>

        <TabsContent value="terminal">
          <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <TerminalPanel />
          </div>
        </TabsContent>

        <TabsContent value="window">
          <div className="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <WindowPanel />
          </div>
        </TabsContent>
      </Tabs>
    </div>
  )
}
