import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { skillsApi } from '@/lib/api/skills'
import toast from 'react-hot-toast'

export function useSkills() {
  return useQuery({
    queryKey: ['skills'],
    queryFn: skillsApi.getSkills,
  })
}

export function useInstallSkill() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: skillsApi.installSkill,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['skills'] })
      toast.success('Skill installed')
    },
    onError: () => {
      toast.error('Failed to install skill')
    },
  })
}

export function useUninstallSkill() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: skillsApi.uninstallSkill,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['skills'] })
      toast.success('Skill uninstalled')
    },
    onError: () => {
      toast.error('Failed to uninstall skill')
    },
  })
}

export function useUpdateSkill() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: skillsApi.updateSkill,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['skills'] })
      toast.success('Skill updated')
    },
    onError: () => {
      toast.error('Failed to update skill')
    },
  })
}

export function useSkillRepos() {
  return useQuery({
    queryKey: ['skills', 'repos'],
    queryFn: skillsApi.getRepos,
  })
}

export function useAddSkillRepo() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: skillsApi.addRepo,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['skills', 'repos'] })
      toast.success('Repository added')
    },
    onError: () => {
      toast.error('Failed to add repository')
    },
  })
}

export function useRemoveSkillRepo() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: skillsApi.removeRepo,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['skills', 'repos'] })
      toast.success('Repository removed')
    },
    onError: () => {
      toast.error('Failed to remove repository')
    },
  })
}
