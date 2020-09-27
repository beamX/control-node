defmodule ControlNode.Host do
  alias ControlNode.Host.SSH

  def upload_file(%SSH{} = host_spec, path, file), do: SSH.upload_file(host_spec, path, file)

  def extract_tar(%SSH{} = host_spec, release_path, release_dir) do
    with {:ok, %SSH.ExecStatus{exit_code: 0}} <-
           SSH.exec(host_spec, "tar -xf #{release_path} -C #{release_dir}") do
      :ok
    end
  end

  def init_release(%SSH{} = host_spec, init_file, command) do
    with {:ok, %SSH.ExecStatus{exit_code: 0}} <-
           SSH.exec(host_spec, "nohup #{init_file} #{command} &", true) do
      :ok
    end
  end
end
