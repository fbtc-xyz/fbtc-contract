// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {Request, UserInfo, RequestLib, Operation, Status, ChainCode} from "./Common.sol";
import {BridgeStorage} from "./base/BridgeStorage.sol";
import {FToken} from "./base/FToken.sol";
import {BasePausableUpgradeable} from "./base/BasePausableUpgradeable.sol";
import {FeeModel} from "./FeeModel.sol";

contract FireBridge is BridgeStorage, BasePausableUpgradeable {
    using RequestLib for Request;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    event QualifiedUserAdded(
        address indexed _user,
        string _depositAddress,
        string _withdrawalAddress
    );
    event QualifiedUserEdited(
        address indexed _user,
        string _depositAddress,
        string _withdrawalAddress
    );
    event QualifiedUserLocked(address indexed _user);
    event QualifiedUserUnlocked(address indexed _user);

    event QualifiedUserRemoved(address indexed _user);

    event TokenSet(address indexed _token);
    event MinterSet(address indexed _minter);
    event FeeModelSet(address indexed _feeModel);
    event FeeRecipientSet(address indexed _feeRecipient);
    event DepositTxBlocked(
        bytes32 indexed _depositTxid,
        uint256 indexed _outputIndex
    );

    event RequestAdded(bytes32 indexed _hash, Operation indexed op, Request _r);
    event RequestConfirmed(bytes32 indexed _hash);

    event FeePaid(address indexed _feeRecipient, uint256 indexed _feeAmount);

    event DstChainAdded(bytes32 indexed _dstChain);
    event DstChainRemoved(bytes32 indexed _dstChain);

    modifier onlyMinter() {
        require(msg.sender == minter, "Caller not minter");
        _;
    }

    modifier onlyActiveQualifiedUser() {
        require(isQualifiedUser(msg.sender), "Caller not qualified");
        require(!userInfo[msg.sender].locked, "Caller locked");
        _;
    }

    bytes32 public immutable MAIN_CHAIN;

    constructor(address _owner, bytes32 _mainChain) {
        initialize(_owner);
        MAIN_CHAIN = _mainChain;
    }

    function initialize(address _owner) public initializer {
        __BasePausableUpgradeable_init(_owner);
    }

    function _splitFeeAndUpdate(Request memory r) internal view {
        uint256 _fee = FeeModel(feeModel).getFee(r);
        r.fee = _fee;
        r.amount = r.amount - _fee;
    }

    function _payFee(uint256 _fee, bool viaMint) internal {
        if (_fee == 0) return;

        address _feeRecipient = feeRecipient;
        if (viaMint) {
            FToken(fbtc).mint(_feeRecipient, _fee);
        } else {
            FToken(fbtc).payFee(msg.sender, _feeRecipient, _fee);
        }
        emit FeePaid(_feeRecipient, _fee);
    }

    function _addRequest(Request memory r) internal returns (bytes32 _hash) {
        require(
            r.nonce == requestHashes.length,
            "Fatal: nonce not equals array length"
        ); // Should never happen.
        _hash = r.getRequestHash();

        // For CrosschainRequest: update extra with self hash.
        if (r.op == Operation.CrosschainRequest) {
            r.extra = abi.encode(_hash);
        }
        requestHashes.push(_hash);
        requests[_hash] = r;
        emit RequestAdded(_hash, r.op, r);
    }

    /// Owner methods.

    /// Qualified user management.
    function addQualifiedUser(
        address _user,
        string calldata _depositAddress,
        string calldata _withdrawalAddress
    ) external onlyOwner {
        require(qualifiedUsers.add(_user), "User already qualified");
        require(
            depositAddressToUser[_depositAddress] == address(0),
            "Deposit address used"
        );
        userInfo[_user] = UserInfo(false, _depositAddress, _withdrawalAddress);
        depositAddressToUser[_depositAddress] = _user;
        emit QualifiedUserAdded(_user, _depositAddress, _withdrawalAddress);
    }

    function editQualifiedUser(
        address _user,
        string calldata _depositAddress,
        string calldata _withdrawalAddress
    ) external onlyOwner {
        require(isQualifiedUser(_user), "User not qualified");
        require(!userInfo[_user].locked, "User locked");

        string memory _oldDepositAddress = userInfo[_user].depositAddress;
        if (
            keccak256(bytes(_depositAddress)) !=
            keccak256(bytes(_oldDepositAddress))
        ) {
            require(
                depositAddressToUser[_depositAddress] == address(0),
                "Deposit address used"
            );
            delete depositAddressToUser[_oldDepositAddress];
            userInfo[_user].depositAddress = _depositAddress;
            depositAddressToUser[_depositAddress] = _user;
        }

        userInfo[_user].withdrawalAddress = _withdrawalAddress;
        emit QualifiedUserEdited(_user, _depositAddress, _withdrawalAddress);
    }

    function removeQualifiedUser(address _qualifiedUser) external onlyOwner {
        require(qualifiedUsers.remove(_qualifiedUser), "User not qualified");
        string memory _depositAddress = userInfo[_qualifiedUser].depositAddress;
        delete depositAddressToUser[_depositAddress];
        delete userInfo[_qualifiedUser];
        emit QualifiedUserRemoved(_qualifiedUser);
    }

    function lockQualifiedUser(address _qualifiedUser) external onlyOwner {
        require(isQualifiedUser(_qualifiedUser), "User not qualified");
        require(!userInfo[_qualifiedUser].locked, "User already locked");
        userInfo[_qualifiedUser].locked = true;
        emit QualifiedUserLocked(_qualifiedUser);
    }

    function unlockQualifiedUser(address _qualifiedUser) external onlyOwner {
        require(isQualifiedUser(_qualifiedUser), "User not qualified");
        require(userInfo[_qualifiedUser].locked, "User not locked");
        userInfo[_qualifiedUser].locked = false;
        emit QualifiedUserUnlocked(_qualifiedUser);
    }

    /// Protocol configuration.
    function setToken(address _token) external onlyOwner {
        fbtc = _token;
        emit TokenSet(_token);
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
        emit MinterSet(_minter);
    }

    function setFeeModel(address _feeModel) external onlyOwner {
        require(_feeModel != address(0), "Invalid feeModel");
        feeModel = _feeModel;
        emit FeeModelSet(_feeModel);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "Invalid feeRecipient");
        feeRecipient = _feeRecipient;
        emit FeeRecipientSet(_feeRecipient);
    }

    function addDstChains(bytes32[] memory _dstChains) external onlyOwner {
        for (uint i = 0; i < _dstChains.length; i++) {
            bytes32 _dstChain = _dstChains[i];
            require(
                _dstChain != MAIN_CHAIN && _dstChain != chain(),
                "Invalid dst chain"
            );
            if (dstChains.add(_dstChain)) {
                emit DstChainAdded(_dstChain);
            }
        }
    }

    function removeDstChains(bytes32[] memory _dstChains) external onlyOwner {
        for (uint i = 0; i < _dstChains.length; i++) {
            bytes32 _dstChain = _dstChains[i];
            if (dstChains.remove(_dstChain)) {
                emit DstChainRemoved(_dstChain);
            }
        }
    }

    /// @notice Mark the deposit tx invalid and reject the minting request if any.
    function blockDepositTx(
        bytes32 _depositTxid,
        uint256 _outputIndex
    ) external onlyOwner {
        bytes32 REJECTED = bytes32(uint256(0xdead));
        bytes memory _depositTxData = abi.encode(_depositTxid, _outputIndex);
        bytes32 depositDataHash = keccak256(_depositTxData);

        bytes32 requestHash = usedDepositTxs[depositDataHash];
        require(requestHash == bytes32(0), "Already confirmed or blocked");

        // Mark it as rejected.
        usedDepositTxs[depositDataHash] = REJECTED;
        emit DepositTxBlocked(_depositTxid, _outputIndex);
    }

    /// QualifiedUser methods.

    /// @notice Initiate a FBTC minting request for the qualifiedUser.
    /// @param _amount The amount of FBTC to mint.
    /// @param _depositTxid The BTC deposit txid
    /// @param _outputIndex The transaction output index to user's deposit address.
    /// @return _hash The hash of the new created request.
    /// @return _r The full new created request.
    function addMintRequest(
        uint256 _amount,
        bytes32 _depositTxid,
        uint256 _outputIndex
    )
        external
        onlyActiveQualifiedUser
        whenNotPaused
        returns (bytes32 _hash, Request memory _r)
    {
        // Check request.
        require(_amount > 0, "Invalid amount");
        require(uint256(_depositTxid) != 0, "Empty deposit txid");
        bytes memory _depositTxData = abi.encode(_depositTxid, _outputIndex);

        bytes32 depositDataHash = keccak256(_depositTxData);
        require(
            usedDepositTxs[depositDataHash] == bytes32(uint256(0)),
            "Used BTC deposit tx"
        );

        // Compose request. Main -> Self
        _r = Request({
            nonce: nonce(),
            op: Operation.Mint,
            srcChain: MAIN_CHAIN,
            srcAddress: bytes(userInfo[msg.sender].depositAddress),
            dstChain: chain(),
            dstAddress: abi.encode(msg.sender),
            amount: _amount,
            fee: 0, // To be set in `_splitFeeAndUpdate`
            extra: _depositTxData,
            status: Status.Pending
        });

        // Split fee.
        _splitFeeAndUpdate(_r);

        // Save request.
        _hash = _addRequest(_r);
    }

    /// @notice Initiate a FBTC burning request for the qualifiedUser.
    /// @param _amount The amount of FBTC to burn.
    /// @return _hash The hash of the new created request.
    /// @return _r The full new created request.
    function addBurnRequest(
        uint256 _amount
    )
        external
        onlyActiveQualifiedUser
        whenNotPaused
        returns (bytes32 _hash, Request memory _r)
    {
        // Check request.
        require(_amount > 0, "Invalid amount");

        // Compose request. Self -> Main
        _r = Request({
            nonce: nonce(),
            op: Operation.Burn,
            srcChain: chain(),
            srcAddress: abi.encode(msg.sender),
            dstChain: MAIN_CHAIN,
            dstAddress: bytes(userInfo[msg.sender].withdrawalAddress),
            amount: _amount,
            fee: 0, // To be set in `_splitFeeAndUpdate`
            extra: "", // Unset until confirmed
            status: Status.Pending
        });

        // Split fee.
        _splitFeeAndUpdate(_r);

        // Save request.
        _hash = _addRequest(_r);

        // Pay fee
        _payFee(_r.fee, false);

        // Burn tokens.
        FToken(fbtc).burn(msg.sender, _r.amount);
    }

    /// Customer methods.

    /// @notice Initiate a FBTC cross-chain bridging request.
    /// @param _targetChain The target chain identifier.
    /// @param _targetAddress The encoded address on the target chain .
    /// @param _amount The amount of FBTC to cross-chain.
    /// @return _hash The hash of the new created request.
    /// @return _r The full new created request.
    function addCrosschainRequest(
        bytes32 _targetChain,
        bytes memory _targetAddress,
        uint256 _amount
    ) public whenNotPaused returns (bytes32 _hash, Request memory _r) {
        // Check request.
        require(_amount > 0, "Invalid amount");
        require(dstChains.contains(_targetChain), "Target chain not allowed");

        // Compose request. Self -> Target
        _r = Request({
            nonce: nonce(),
            op: Operation.CrosschainRequest,
            srcChain: chain(),
            srcAddress: abi.encode(msg.sender),
            amount: _amount,
            dstChain: _targetChain,
            dstAddress: _targetAddress,
            fee: 0,
            extra: "", // Not include in hash.
            status: Status.Unused // Not used.
        });

        // Split fee.
        _splitFeeAndUpdate(_r);

        // Save request.
        _hash = _addRequest(_r);

        // Pay fee
        _payFee(_r.fee, false);

        // Burn tokens.
        FToken(fbtc).burn(msg.sender, _r.amount);
    }

    /// @notice A more user-friendly interface to cross-chain to an
    ///         EVM-compatible target chain.
    /// @param _targetChainId The chain id of target EVM chain.
    /// @param _targetAddress The target EVM address.
    /// @param _amount The amount of FBTC to cross-chain.
    /// @return _hash The hash of the new created request.
    /// @return _r The full new created request.
    function addEVMCrosschainRequest(
        uint256 _targetChainId,
        address _targetAddress,
        uint256 _amount
    ) external returns (bytes32 _hash, Request memory _r) {
        return
            addCrosschainRequest(
                bytes32(_targetChainId),
                abi.encode(_targetAddress),
                _amount
            );
    }

    /// Minter methods.

    /// @notice Confirm the minting request.
    /// @param _hash The minting request hash.
    function confirmMintRequest(
        bytes32 _hash
    ) external onlyMinter whenNotPaused {
        // Check request.
        Request storage r = requests[_hash];
        require(r.op == Operation.Mint, "Not Mint request");

        uint256 _amount = r.amount;
        require(_amount > 0, "Invalid request amount");
        require(r.status == Status.Pending, "Invalid request status");

        // Check and update deposit data usage status.
        bytes32 depositDataHash = keccak256(r.extra);
        require(
            usedDepositTxs[depositDataHash] == bytes32(uint256(0)),
            "Used BTC deposit tx"
        );
        usedDepositTxs[depositDataHash] = _hash;

        // Update status.
        r.status = Status.Confirmed;
        emit RequestConfirmed(_hash);

        // Mint tokens
        FToken(fbtc).mint(abi.decode(r.dstAddress, (address)), _amount);

        // Pay fee.
        _payFee(r.fee, true);
    }

    /// @notice Confirm the burning request.
    /// @dev `_withdrawalTxData` packing format is defined by off-chain service.
    /// @param _hash The burning request id.
    /// @param _withdrawalTxid The BTC withdrawal txid
    /// @param _outputIndex The transaction output index to user's withdrawal address.
    function confirmBurnRequest(
        bytes32 _hash,
        bytes32 _withdrawalTxid,
        uint256 _outputIndex
    ) external onlyMinter whenNotPaused {
        // Check request.
        require(uint256(_withdrawalTxid) != 0, "Empty withdraw txid");

        Request storage r = requests[_hash];

        require(r.op == Operation.Burn, "Not Burn request");
        require(r.amount > 0, "Invalid request amount");
        require(r.status == Status.Pending, "Invalid request status");

        bytes memory _withdrawalTxData = abi.encode(
            _withdrawalTxid,
            _outputIndex
        );

        bytes32 _withdrawalDataHash = keccak256(_withdrawalTxData);
        require(
            usedWithdrawalTxs[_withdrawalDataHash] == bytes32(uint256(0)),
            "Used BTC withdrawal tx"
        );
        usedWithdrawalTxs[_withdrawalDataHash] = _hash;

        // Update status.
        r.status = Status.Confirmed;
        r.extra = _withdrawalTxData;

        emit RequestConfirmed(_hash);
    }

    /// @notice Confirm the cross-chain request.
    /// @dev Most fields of the request should be the same as the one on
    ///      source chain. Note:
    ///       1. The `op` should be `CrosschainConfirm`
    ///       2. The `nonce` is the source nonce, used to calc source request hash.
    ///       3. The `status` should be `Unused` (0).
    ///       4. The `extra` should be 32 bytes length and contain the source request hash.
    /// @param r The full cross-chain request.
    function confirmCrosschainRequest(
        Request memory r
    ) external onlyMinter whenNotPaused {
        // Check request.
        require(r.amount > 0, "Invalid request amount");
        require(r.dstChain == chain(), "Dst chain not match");
        require(
            r.op == Operation.CrosschainConfirm,
            "Not CrosschainConfirm request"
        );
        require(r.status == Status.Unused, "Status should not be used");

        require(r.extra.length == 32, "Invalid extra: not valid bytes32");
        require(
            r.dstAddress.length == 32,
            "Invalid dstAddress: not 32 bytes length"
        );
        require(
            abi.decode(r.dstAddress, (uint256)) <= type(uint160).max,
            "Invalid dstAddress: not address"
        );

        bytes32 srcHash = abi.decode(r.extra, (bytes32));

        // Set to request to calc hash.
        require(
            r.getCrossSourceRequestHash() == srcHash,
            "Source request hash is incorrect"
        );
        require(
            crosschainRequestConfirmation[srcHash] == bytes32(0),
            "Source request already confirmed"
        );

        // Save request.
        r.nonce = nonce(); // Override src nonce to dst nonce.
        bytes32 _dsthash = _addRequest(r);
        crosschainRequestConfirmation[srcHash] = _dsthash;

        // Mint tokens.
        FToken(fbtc).mint(abi.decode(r.dstAddress, (address)), r.amount);
    }

    /// View functions.

    /// @notice The unique chain identifier in FBTC system.
    function chain() public view returns (bytes32) {
        return ChainCode.getSelfChainCode();
    }

    /// @notice The next request id
    function nonce() public view returns (uint128) {
        require(
            requestHashes.length < type(uint128).max,
            "Fatal: nonce overflow"
        ); // Unlikely happens.
        return uint128(requestHashes.length);
    }

    /// @notice Check whether the address is qualified
    function isQualifiedUser(address _user) public view returns (bool) {
        return qualifiedUsers.contains(_user);
    }

    /// @notice Check whether the address is qualified and active
    function isActiveUser(address _user) public view returns (bool) {
        return isQualifiedUser(_user) && !userInfo[_user].locked;
    }

    /// @notice Get all qualified users
    function getQualifiedUsers() external view returns (address[] memory) {
        return qualifiedUsers.values();
    }

    /// @notice Get all active users
    function getActiveUsers() external view returns (address[] memory _users) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < qualifiedUsers.length(); ++i) {
            UserInfo storage info = userInfo[qualifiedUsers.at(i)];
            if (!info.locked) {
                activeCount += 1;
            }
        }

        _users = new address[](activeCount);
        uint256 j = 0;
        for (uint256 i = 0; i < qualifiedUsers.length(); ++i) {
            address _user = qualifiedUsers.at(i);
            UserInfo storage info = userInfo[_user];
            if (!info.locked) {
                _users[j++] = _user;
            }
        }
    }

    /// @notice Get qualified user information.
    function getQualifiedUserInfo(
        address _user
    ) external view returns (UserInfo memory info) {
        info = userInfo[_user];
    }

    /// @notice Get qualified user information.
    function getValidDstChains() external view returns (bytes32[] memory) {
        return dstChains.values();
    }

    /// @notice Get request by the index a.k.a the id.
    /// @param _id The index.
    /// @return r The returned request.
    function getRequestById(
        uint256 _id
    ) external view returns (Request memory r) {
        require(_id < requestHashes.length, "Request not exists");
        r = requests[requestHashes[_id]];
    }

    /// @notice Get multiple requests by an id range.
    /// @param _start The start index.
    /// @param _end The end index.
    /// @return rs The returned requests.
    function getRequestsByIdRange(
        uint256 _start,
        uint256 _end
    ) external view returns (Request[] memory rs) {
        uint256 maxIndex = requestHashes.length - 1;
        if (_end > maxIndex) _end = maxIndex;
        require(_start <= _end, "start should <= end");
        uint256 len = _end - _start + 1;
        rs = new Request[](len);
        for (uint i = 0; i < len; i++) {
            rs[i] = requests[requestHashes[i + _start]];
        }
    }

    /// @notice Get request by hash
    /// @param _hash The hash
    /// @return r The returned request.
    function getRequestByHash(
        bytes32 _hash
    ) public view returns (Request memory r) {
        r = requests[_hash];
        require(r.op != Operation.Nop, "Request not exists");
    }

    /// @notice Get multiple requests by hashes.
    /// @param _hashes The hash list
    /// @return rs The returned requests.
    function getRequestsByHashes(
        bytes32[] calldata _hashes
    ) external view returns (Request[] memory rs) {
        rs = new Request[](_hashes.length);
        for (uint i = 0; i < _hashes.length; i++) {
            rs[i] = getRequestByHash(_hashes[i]);
        }
    }

    /// @notice Calculate hash of the request.
    /// @param _r The Request to hash
    /// @return _hash The hash result
    function calculateRequestHash(
        Request memory _r
    ) external pure returns (bytes32 _hash) {
        _hash = _r.getRequestHash();
    }
}
