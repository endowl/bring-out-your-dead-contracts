pragma solidity ^0.6.0;

interface ModuleManager {
  function enableModule ( address module ) external;
  function disableModule ( address prevModule, address module ) external;
  function execTransactionFromModule ( address to, uint256 value, bytes calldata data, uint8 operation ) external returns ( bool success );
  function execTransactionFromModuleReturnData ( address to, uint256 value, bytes calldata data, uint8 operation ) external returns ( bool success, bytes memory returnData );
  function getModules (  ) external view returns ( address[] memory );
  function getModulesPaginated ( address start, uint256 pageSize ) external view returns ( address[] memory array, address next );
}
